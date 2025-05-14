/*
 * Copyright (c) 2018 - 2019 YCSB contributors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. See accompanying
 * LICENSE file.
 */

package site.ycsb.db.rocksdb;

import site.ycsb.*;
import site.ycsb.Status;
import net.jcip.annotations.GuardedBy;
import org.rocksdb.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

import static java.nio.charset.StandardCharsets.UTF_8;

/**
 * RocksDB binding for <a href="http://rocksdb.org/">RocksDB</a>.
 *
 * See {@code rocksdb/README.md} for details.
 */
public class RocksDBClient extends DB {

  static final String PROPERTY_ROCKSDB_DIR = "rocksdb.dir";
  static final String PROPERTY_ROCKSDB_OPTIONS_FILE = "rocksdb.optionsfile";
  private static final String COLUMN_FAMILY_NAMES_FILENAME = "CF_NAMES";

  private static final Logger LOGGER = LoggerFactory.getLogger(RocksDBClient.class);

  @GuardedBy("RocksDBClient.class")
  private static Path rocksDbDir = null;
  @GuardedBy("RocksDBClient.class")
  private static Path optionsFile = null;
  @GuardedBy("RocksDBClient.class")
  private static RocksObject dbOptions = null; // This holds DBOptions or Options
  @GuardedBy("RocksDBClient.class")
  private static RocksDB rocksDb = null;
  @GuardedBy("RocksDBClient.class")
  private static int references = 0;

  private static final ConcurrentMap<String, ColumnFamily> COLUMN_FAMILIES = new ConcurrentHashMap<>();
  private static final ConcurrentMap<String, Lock> COLUMN_FAMILY_LOCKS = new ConcurrentHashMap<>();

  @Override
  public void init() throws DBException {
    synchronized (RocksDBClient.class) {
      if (rocksDb == null) {
        rocksDbDir = Paths.get(getProperties().getProperty(PROPERTY_ROCKSDB_DIR));
        LOGGER.info("RocksDB data dir: " + rocksDbDir);

        String optionsFileString = getProperties().getProperty(PROPERTY_ROCKSDB_OPTIONS_FILE);
        if (optionsFileString != null) {
          optionsFile = Paths.get(optionsFileString);
          LOGGER.info("RocksDB options file: " + optionsFile);
        }

        try {
          if (optionsFile != null) {
            rocksDb = initRocksDBWithOptionsFile();
          } else {
            rocksDb = initRocksDB();
          }
        } catch (final IOException | RocksDBException e) {
          throw new DBException(e);
        }
      }

      references++;
    }
  }

  /**
   * Initializes and opens the RocksDB database using an options file.
   *
   * Should only be called with a
   * {@code synchronized(RocksDBClient.class)` block}.
   *
   * @return The initialized and open RocksDB instance.
   */
  private RocksDB initRocksDBWithOptionsFile() throws IOException, RocksDBException {
    if (!Files.exists(rocksDbDir)) {
      Files.createDirectories(rocksDbDir);
    }

    final DBOptions options = new DBOptions(); // This is the DBOptions object to be populated
    final List<ColumnFamilyDescriptor> cfDescriptors = new ArrayList<>();
    final List<ColumnFamilyHandle> cfHandles = new ArrayList<>();

    RocksDB.loadLibrary();

    // ---- MODIFICATION FOR NEW RocksDB JNI API ----
    final ConfigOptions configOptions = new ConfigOptions(); // Create ConfigOptions
    // Call the new method signature for loadOptionsFromFile
    OptionsUtil.loadOptionsFromFile(configOptions, optionsFile.toAbsolutePath().toString(), options, cfDescriptors);
    // ---- END MODIFICATION ----

    dbOptions = options; // Assign the populated DBOptions

    final RocksDB db = RocksDB.open(options, rocksDbDir.toAbsolutePath().toString(), cfDescriptors, cfHandles);

    for (int i = 0; i < cfDescriptors.size(); i++) {
      String cfName = new String(cfDescriptors.get(i).getName());
      final ColumnFamilyHandle cfHandle = cfHandles.get(i);
      // final ColumnFamilyOptions cfOptions = cfDescriptors.get(i).getOptions(); //
      // This will give ColumnFamilyOptions
      // from descriptor that might be closed if
      // options itself is closed too early.
      // It's safer to get options from the handle if needed
      // or ensure options object lifetime.
      // However, the ColumnFamily class stores this.

      // Let's re-get options from the descriptor to be safe for storage in
      // ColumnFamily
      final ColumnFamilyOptions currentCfOptions = cfDescriptors.get(i).getOptions();
      COLUMN_FAMILIES.put(cfName, new ColumnFamily(cfHandle, currentCfOptions));
    }

    return db;
  }

  /**
   * Initializes and opens the RocksDB database with default options or loaded
   * CFs.
   *
   * Should only be called with a
   * {@code synchronized(RocksDBClient.class)` block}.
   *
   * @return The initialized and open RocksDB instance.
   */
  private RocksDB initRocksDB() throws IOException, RocksDBException {
    if (!Files.exists(rocksDbDir)) {
      Files.createDirectories(rocksDbDir);
    }

    final List<String> cfNames = loadColumnFamilyNames();
    final List<ColumnFamilyOptions> cfOptionss = new ArrayList<>();
    final List<ColumnFamilyDescriptor> cfDescriptors = new ArrayList<>();

    for (final String cfName : cfNames) {
      final ColumnFamilyOptions cfOptions = new ColumnFamilyOptions()
          .optimizeLevelStyleCompaction();
      final ColumnFamilyDescriptor cfDescriptor = new ColumnFamilyDescriptor(
          cfName.getBytes(UTF_8),
          cfOptions);
      cfOptionss.add(cfOptions);
      cfDescriptors.add(cfDescriptor);
    }

    final int rocksThreads = Runtime.getRuntime().availableProcessors() * 2;

    if (cfDescriptors.isEmpty()) {
      final Options options = new Options()
          .optimizeLevelStyleCompaction()
          .setCreateIfMissing(true)
          .setCreateMissingColumnFamilies(true) // Though no missing CFs are specified here initially
          .setIncreaseParallelism(rocksThreads)
          .setMaxBackgroundCompactions(rocksThreads)
          .setInfoLogLevel(InfoLogLevel.INFO_LEVEL);
      dbOptions = options;
      return RocksDB.open(options, rocksDbDir.toAbsolutePath().toString());
    } else {
      final DBOptions options = new DBOptions()
          .setCreateIfMissing(true)
          .setCreateMissingColumnFamilies(true)
          .setIncreaseParallelism(rocksThreads)
          .setMaxBackgroundCompactions(rocksThreads)
          .setInfoLogLevel(InfoLogLevel.INFO_LEVEL);
      dbOptions = options;

      final List<ColumnFamilyHandle> cfHandles = new ArrayList<>();
      final RocksDB db = RocksDB.open(options, rocksDbDir.toAbsolutePath().toString(), cfDescriptors, cfHandles);
      for (int i = 0; i < cfNames.size(); i++) {
        // Ensure we use the specific CFOptions that were used to create/open the CF
        COLUMN_FAMILIES.put(cfNames.get(i), new ColumnFamily(cfHandles.get(i), cfDescriptors.get(i).getOptions()));
      }
      return db;
    }
  }

  @Override
  public void cleanup() throws DBException {
    super.cleanup();

    synchronized (RocksDBClient.class) {
      try {
        if (references == 1) {
          for (final ColumnFamily cf : COLUMN_FAMILIES.values()) {
            cf.getHandle().close();
            // ColumnFamilyOptions stored in ColumnFamily objects should also be closed if
            // they are not shared
            // or if they are not the same as dbOptions (which they are not in case of
            // multiple CFs)
            cf.getOptions().close();
          }
          COLUMN_FAMILIES.clear(); // Clear after closing options and handles

          if (rocksDb != null) {
            rocksDb.close();
            rocksDb = null;
          }

          if (dbOptions != null) {
            dbOptions.close(); // dbOptions is Options or DBOptions, both are RocksObject and closeable
            dbOptions = null;
          }

          // cfOptions from descriptors were stored in COLUMN_FAMILIES and should be
          // closed above.
          saveColumnFamilyNames(); // Save names before clearing rocksDbDir reference

          rocksDbDir = null; // Nullify after all operations needing it are done
          optionsFile = null;
        }

      } catch (final IOException e) { // RocksDBException can also be thrown by close methods
        throw new DBException(e);
      } finally {
        if (references > 0) { // Ensure references is decremented only if it was positive
          references--;
        }
      }
    }
  }

  @Override
  public Status read(final String table, final String key, final Set<String> fields,
      final Map<String, ByteIterator> result) {
    try {
      if (!COLUMN_FAMILIES.containsKey(table)) {
        createColumnFamily(table);
      }

      final ColumnFamilyHandle cf = COLUMN_FAMILIES.get(table).getHandle();
      final byte[] values = rocksDb.get(cf, key.getBytes(UTF_8));
      if (values == null) {
        return Status.NOT_FOUND;
      }
      deserializeValues(values, fields, result);
      return Status.OK;
    } catch (final RocksDBException e) {
      LOGGER.error(e.getMessage(), e);
      return Status.ERROR;
    }
  }

  @Override
  public Status scan(final String table, final String startkey, final int recordcount, final Set<String> fields,
      final Vector<HashMap<String, ByteIterator>> result) {
    try {
      if (!COLUMN_FAMILIES.containsKey(table)) {
        createColumnFamily(table);
      }

      final ColumnFamilyHandle cf = COLUMN_FAMILIES.get(table).getHandle();
      try (final RocksIterator iterator = rocksDb.newIterator(cf)) {
        int iterations = 0;
        for (iterator.seek(startkey.getBytes(UTF_8)); iterator.isValid() && iterations < recordcount; iterator.next()) {
          final HashMap<String, ByteIterator> values = new HashMap<>();
          deserializeValues(iterator.value(), fields, values);
          result.add(values);
          iterations++;
        }
      }

      return Status.OK;
    } catch (final RocksDBException e) {
      LOGGER.error(e.getMessage(), e);
      return Status.ERROR;
    }
  }

  @Override
  public Status update(final String table, final String key, final Map<String, ByteIterator> values) {
    // TODO(AR) consider if this would be faster with merge operator

    try {
      if (!COLUMN_FAMILIES.containsKey(table)) {
        createColumnFamily(table);
      }

      final ColumnFamilyHandle cf = COLUMN_FAMILIES.get(table).getHandle();
      final Map<String, ByteIterator> result = new HashMap<>();
      final byte[] currentValues = rocksDb.get(cf, key.getBytes(UTF_8));
      if (currentValues == null) {
        // Original YCSB core doesn't expect update to fail if key not found, it would
        // just insert.
        // However, this implementation tries to read first. For strict "update only if
        // exists",
        // this is correct. If "upsert" is desired, behavior might need adjustment or
        // rely on insert.
        // For now, keeping existing logic.
        LOGGER.warn("Key not found during update operation. Table: {}, Key: {}", table, key);
        return Status.NOT_FOUND; // Or Status.ERROR if update implies key must exist
      }
      deserializeValues(currentValues, null, result);

      // update
      result.putAll(values);

      // store
      rocksDb.put(cf, key.getBytes(UTF_8), serializeValues(result));

      return Status.OK;

    } catch (final RocksDBException | IOException e) {
      LOGGER.error(e.getMessage(), e);
      return Status.ERROR;
    }
  }

  @Override
  public Status insert(final String table, final String key, final Map<String, ByteIterator> values) {
    try {
      if (!COLUMN_FAMILIES.containsKey(table)) {
        createColumnFamily(table);
      }

      final ColumnFamilyHandle cf = COLUMN_FAMILIES.get(table).getHandle();
      rocksDb.put(cf, key.getBytes(UTF_8), serializeValues(values));

      return Status.OK;
    } catch (final RocksDBException | IOException e) {
      LOGGER.error(e.getMessage(), e);
      return Status.ERROR;
    }
  }

  @Override
  public Status delete(final String table, final String key) {
    try {
      if (!COLUMN_FAMILIES.containsKey(table)) {
        // If CF must exist for delete, this is fine. If deleting from non-existent CF
        // should be no-op:
        // LOGGER.warn("Column family {} does not exist for delete operation on key {}.
        // Assuming NOT_FOUND.", table, key);
        // return Status.NOT_FOUND; // Or OK, depending on desired semantics.
        // For now, will proceed to create it, which might be unexpected for a delete.
        // A safer approach might be to check and return NOT_FOUND if CF doesn't exist.
        createColumnFamily(table); // This behavior (creating CF on delete if not exists) might be surprising.
      }

      final ColumnFamilyHandle cf = COLUMN_FAMILIES.get(table).getHandle();
      rocksDb.delete(cf, key.getBytes(UTF_8));

      return Status.OK;
    } catch (final RocksDBException e) {
      LOGGER.error(e.getMessage(), e);
      return Status.ERROR;
    }
  }

  private void saveColumnFamilyNames() throws IOException {
    if (rocksDbDir == null) { // Guard against null rocksDbDir if cleanup is called multiple times or out of
                              // order
      LOGGER.warn("rocksDbDir is null during saveColumnFamilyNames, skipping.");
      return;
    }
    final Path file = rocksDbDir.resolve(COLUMN_FAMILY_NAMES_FILENAME);
    try (final PrintWriter writer = new PrintWriter(Files.newBufferedWriter(file, UTF_8))) {
      writer.println(new String(RocksDB.DEFAULT_COLUMN_FAMILY, UTF_8)); // Always save default
      for (final String cfName : COLUMN_FAMILIES.keySet()) {
        if (!cfName.equals(new String(RocksDB.DEFAULT_COLUMN_FAMILY, UTF_8))) { // Avoid duplicate default
          writer.println(cfName);
        }
      }
    }
  }

  private List<String> loadColumnFamilyNames() throws IOException {
    final List<String> cfNames = new ArrayList<>();
    if (rocksDbDir == null) { // Guard against null rocksDbDir
      LOGGER.warn("rocksDbDir is null during loadColumnFamilyNames, returning empty list.");
      return cfNames;
    }
    final Path file = rocksDbDir.resolve(COLUMN_FAMILY_NAMES_FILENAME);
    if (Files.exists(file)) {
      try (final LineNumberReader reader = new LineNumberReader(Files.newBufferedReader(file, UTF_8))) {
        String line;
        while ((line = reader.readLine()) != null) {
          if (!line.isEmpty() && !cfNames.contains(line)) { // Ensure unique names
            cfNames.add(line);
          }
        }
      }
    }
    // Ensure default CF is always considered if no names are loaded,
    // as RocksDB.open() without CFs opens default.
    // However, the logic in initRocksDB handles empty cfDescriptors by using
    // Options not DBOptions.
    // If cfNames is empty, it means we should open with default column family
    // implicitly.
    // The current logic to add "default" if empty might be redundant if RocksDB
    // handles it.
    // For now, if file doesn't exist or is empty, it will try to open default via
    // `new Options()`.
    // If file has names, it will use those.
    return cfNames;
  }

  private Map<String, ByteIterator> deserializeValues(final byte[] values, final Set<String> fields,
      final Map<String, ByteIterator> result) {
    final ByteBuffer buf = ByteBuffer.allocate(4); // Reused for reading lengths

    int offset = 0;
    while (offset < values.length) {
      // Protect against buffer underflow if data is malformed
      if (offset + 4 > values.length) {
        LOGGER.error("Error deserializing, not enough data for key length. Offset: {}, Total Length: {}", offset,
            values.length);
        break;
      }
      buf.put(values, offset, 4);
      buf.flip();
      final int keyLen = buf.getInt();
      buf.clear();
      offset += 4;

      if (offset + keyLen > values.length) {
        LOGGER.error("Error deserializing, not enough data for key. KeyLen: {}, Offset: {}, Total Length: {}", keyLen,
            offset, values.length);
        break;
      }
      final String key = new String(values, offset, keyLen, UTF_8); // Specify charset
      offset += keyLen;

      if (offset + 4 > values.length) {
        LOGGER.error("Error deserializing, not enough data for value length. Offset: {}, Total Length: {}", offset,
            values.length);
        break;
      }
      buf.put(values, offset, 4);
      buf.flip();
      final int valueLen = buf.getInt();
      buf.clear();
      offset += 4;

      if (offset + valueLen > values.length) {
        LOGGER.error("Error deserializing, not enough data for value. ValueLen: {}, Offset: {}, Total Length: {}",
            valueLen, offset, values.length);
        break;
      }

      if (fields == null || fields.contains(key)) {
        result.put(key, new ByteArrayByteIterator(values, offset, valueLen));
      }

      offset += valueLen;
    }

    return result;
  }

  private byte[] serializeValues(final Map<String, ByteIterator> values) throws IOException {
    try (final ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
      final ByteBuffer buf = ByteBuffer.allocate(4); // Reused for writing lengths

      for (final Map.Entry<String, ByteIterator> value : values.entrySet()) {
        final byte[] keyBytes = value.getKey().getBytes(UTF_8); // Specify charset
        final byte[] valueBytes = value.getValue().toArray();

        buf.putInt(keyBytes.length);
        baos.write(buf.array()); // Writes the entire buffer, make sure it's just the int
        buf.clear(); // Clear before next use (putInt fills from position 0)

        baos.write(keyBytes);

        buf.putInt(valueBytes.length);
        baos.write(buf.array());
        buf.clear();

        baos.write(valueBytes);
      }
      return baos.toByteArray();
    }
  }

  private ColumnFamilyOptions getDefaultColumnFamilyOptions(final String destinationCfName) {
    final ColumnFamilyOptions cfOptions;

    // Check if "default" CF's options are loaded and available from an options file
    final ColumnFamily defaultCfFromLoadedOptions = COLUMN_FAMILIES
        .get(new String(RocksDB.DEFAULT_COLUMN_FAMILY, UTF_8));

    if (defaultCfFromLoadedOptions != null) {
      LOGGER.warn("No column family options for \"{}\" in options file - using options from \"default\" column family.",
          destinationCfName);
      // IMPORTANT: Must create a new ColumnFamilyOptions object from the existing
      // one.
      // Reusing the same options object can lead to it being closed prematurely if
      // "default" CF is closed.
      cfOptions = new ColumnFamilyOptions(defaultCfFromLoadedOptions.getOptions());
    } else {
      LOGGER.warn(
          "No column family options for either \"{}\" or \"default\" in options file - initializing with empty configuration.",
          destinationCfName);
      cfOptions = new ColumnFamilyOptions(); // Default, basic options
    }
    // The warning below might be too strong if default behavior is acceptable.
    // LOGGER.warn("Add a CFOptions section for \"" + destinationCfName + "\" to the
    // options file, " +
    // "or subsequent runs on this DB will fail.");

    return cfOptions;
  }

  private void createColumnFamily(final String name) throws RocksDBException {
    COLUMN_FAMILY_LOCKS.putIfAbsent(name, new ReentrantLock());

    final Lock l = COLUMN_FAMILY_LOCKS.get(name);
    l.lock();
    try {
      if (!COLUMN_FAMILIES.containsKey(name)) {
        final ColumnFamilyOptions cfOptions;

        if (optionsFile != null) {
          // If an options file is used, it should define all necessary column families.
          // The `loadOptionsFromFile` populates COLUMN_FAMILIES map.
          // If a CF is not in the options file, we might use default settings.
          // However, `getDefaultColumnFamilyOptions` tries to get options from the
          // "default" CF
          // that should have been loaded from the options file.
          ColumnFamilyDescriptor existingDescriptor = null;
          if (dbOptions instanceof DBOptions) { // dbOptions holds the main DBOptions loaded from file
            // This check is a bit convoluted. The cfDescriptors list from
            // initRocksDBWithOptionsFile is not kept.
            // We assume that if optionsFile was used, all CFs were loaded.
            // A simpler approach if CF is not found after options file loading:
            // 1. Disallow on-the-fly creation if options file is strict.
            // 2. Use truly default options.
            // The current getDefaultColumnFamilyOptions tries to find 'default' CF's
            // options from loaded set.
            LOGGER.warn("Attempting to create column family '{}' not explicitly defined in options file. " +
                "Using default options or options from 'default' CF if defined in file.", name);
            cfOptions = getDefaultColumnFamilyOptions(name);

          } else { // No options file, or optionsFile loading didn't produce DBOptions (should not
                   // happen if optionsFile is not null)
            cfOptions = new ColumnFamilyOptions().optimizeLevelStyleCompaction();
          }
        } else { // No options file at all
          cfOptions = new ColumnFamilyOptions().optimizeLevelStyleCompaction();
        }

        final ColumnFamilyHandle cfHandle = rocksDb.createColumnFamily(
            new ColumnFamilyDescriptor(name.getBytes(UTF_8), cfOptions) // cfOptions passed here must not be closed
                                                                        // elsewhere prematurely
        );
        // Store the newly created cfOptions with the handle. It's owned by this CF now.
        COLUMN_FAMILIES.put(name, new ColumnFamily(cfHandle, cfOptions));
      }
    } finally {
      l.unlock();
    }
  }

  private static final class ColumnFamily {
    private final ColumnFamilyHandle handle;
    private final ColumnFamilyOptions options; // This CF owns these options now

    private ColumnFamily(final ColumnFamilyHandle handle, final ColumnFamilyOptions options) {
      this.handle = handle;
      this.options = options;
    }

    public ColumnFamilyHandle getHandle() {
      return handle;
    }

    public ColumnFamilyOptions getOptions() {
      return options;
    }
  }
}