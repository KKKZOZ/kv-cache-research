/**
 * CacheLib client implementation for YCSB.
 */
package site.ycsb.db.cachelib;

import site.ycsb.*;

import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.io.*;

import java.nio.charset.StandardCharsets;

/**
 * CacheLibClient implements YCSB DB interface using native CacheLib via JNI.
 */
public class CacheLibClient extends DB {

  static {
    System.loadLibrary("cachelibjni");
  }

  /** Flag to ensure native initialization only happens once. */
  private static final AtomicBoolean INITIALIZED = new AtomicBoolean(false);

  // JNI native 方法声明
  private native void nativeInit(String config);
  private native void nativeCleanup();
  private native boolean nativeInsert(String table, String key, byte[] value);
  private native byte[] nativeRead(String table, String key);
  private native boolean nativeUpdate(String table, String key, byte[] value);
  private native boolean nativeDelete(String table, String key);

  @Override
  public void init() {
    if (INITIALIZED.compareAndSet(false, true)) {
      String configPath = getProperties().getProperty("cachelib.config");
      if (configPath == null || configPath.isEmpty()) {
        throw new RuntimeException("Missing required property: cachelib.config");
      }
      try {
        nativeInit(configPath);
      } catch (Exception e) {
        INITIALIZED.set(false);
        throw new RuntimeException("CacheLib native init failed", e);
      }
    }
  }

  @Override
  public void cleanup() {
    if (INITIALIZED.compareAndSet(true, false)) {
      nativeCleanup();
    }
  }

  @Override
  public Status insert(String table, String key, Map<String, ByteIterator> values) {
    byte[] value = serialize(values);
    return nativeInsert(table, key, value) ? Status.OK : Status.ERROR;
  }

  @Override
  public Status read(String table, String key, Set<String> fields, Map<String, ByteIterator> result) {
    byte[] value = nativeRead(table, key);
    if (value == null) {
      return Status.NOT_FOUND;
    }
    deserialize(value, fields, result);
    return Status.OK;
  }

  @Override
  public Status update(String table, String key, Map<String, ByteIterator> values) {
    byte[] value = serialize(values);
    return nativeUpdate(table, key, value) ? Status.OK : Status.ERROR;
  }

  @Override
  public Status delete(String table, String key) {
    return nativeDelete(table, key) ? Status.OK : Status.ERROR;
  }

  /**
   * Serialize a map of ByteIterator values into a byte array.
   */
  private byte[] serialize(Map<String, ByteIterator> values) {
    try (ByteArrayOutputStream baos = new ByteArrayOutputStream();
        DataOutputStream dos = new DataOutputStream(baos)) {

      for (Map.Entry<String, ByteIterator> entry : values.entrySet()) {
        byte[] keyBytes = entry.getKey().getBytes(StandardCharsets.UTF_8);
        ByteIterator it = entry.getValue();

        byte[] valueBytes = it.toArray();  // 用 toArray() 替代手动遍历 next()

        dos.writeInt(keyBytes.length);
        dos.write(keyBytes);
        dos.writeInt(valueBytes.length);
        dos.write(valueBytes);
      }

      dos.flush();
      return baos.toByteArray();
    } catch (IOException e) {
      throw new RuntimeException("Serialization failed", e);
    }
  }
  

  /**
   * Deserialize a byte array into a map of ByteIterator values.
   */
  private void deserialize(byte[] bytes, Set<String> fields, Map<String, ByteIterator> result) {
    try (ByteArrayInputStream bais = new ByteArrayInputStream(bytes);
         DataInputStream dis = new DataInputStream(bais)) {

      while (dis.available() > 0) {
        int keyLen = dis.readInt();
        byte[] keyBytes = new byte[keyLen];
        dis.readFully(keyBytes);
        String key = new String(keyBytes, StandardCharsets.UTF_8);

        int valLen = dis.readInt();
        byte[] valBytes = new byte[valLen];
        dis.readFully(valBytes);

        if (fields == null || fields.contains(key)) {
          result.put(key, new ByteArrayByteIterator(valBytes));
        }
      }
    } catch (IOException e) {
      throw new RuntimeException("Deserialization failed", e);
    }
  }

  @Override
  public Status scan(String table, String startkey, int recordcount,
                     Set<String> fields, Vector<HashMap<String, ByteIterator>> result) {
    // TODO: Implement range scan if CacheLib supports it
    return Status.NOT_IMPLEMENTED;
  }
}