#include "site_ycsb_db_cachelib_CacheLibClient.h"
#include "CacheLibWrapper.h"

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>

// 全局 CacheLib 实例及保护锁（防止多线程竞争）
static CacheLibWrapper* g_cache = nullptr;
static std::mutex g_cache_mutex;

// 将 jstring 转换为 std::string
static std::string JStringToStdString(JNIEnv* env, jstring jstr) {
    if (!jstr) return "";
    const char* utfChars = env->GetStringUTFChars(jstr, nullptr);
    std::string result(utfChars ? utfChars : "");
    if (utfChars) env->ReleaseStringUTFChars(jstr, utfChars);
    return result;
}

JNIEXPORT void JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeInit
  (JNIEnv* env, jobject, jstring jconfigPath) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (g_cache) {
        delete g_cache;
        g_cache = nullptr;
    }
    std::string configPath = JStringToStdString(env, jconfigPath);
    try {
        g_cache = new CacheLibWrapper(configPath);
    } catch (const std::exception& ex) {
        g_cache = nullptr;
        // 抛出Java异常
        jclass exClass = env->FindClass("java/lang/RuntimeException");
        env->ThrowNew(exClass, ex.what());
    }
}

JNIEXPORT void JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeCleanup
  (JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (g_cache) {
        delete g_cache;
        g_cache = nullptr;
    }
}

JNIEXPORT jboolean JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeInsert
  (JNIEnv* env, jobject, jstring, jstring jkey, jbyteArray jvalue) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (!g_cache) return JNI_FALSE;

    std::string key = JStringToStdString(env, jkey);

    jsize len = env->GetArrayLength(jvalue);
    std::vector<uint8_t> value(len);
    env->GetByteArrayRegion(jvalue, 0, len, reinterpret_cast<jbyte*>(value.data()));

    bool ok = g_cache->insert(key, value);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeRead
  (JNIEnv* env, jobject, jstring, jstring jkey) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (!g_cache) return nullptr;

    std::string key = JStringToStdString(env, jkey);
    std::vector<uint8_t> value;

    bool found = g_cache->read(key, value);
    if (!found) {
        return nullptr;
    }

    jbyteArray jret = env->NewByteArray(static_cast<jsize>(value.size()));
    env->SetByteArrayRegion(jret, 0, static_cast<jsize>(value.size()), reinterpret_cast<const jbyte*>(value.data()));
    return jret;
}

JNIEXPORT jboolean JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeUpdate
  (JNIEnv* env, jobject, jstring, jstring jkey, jbyteArray jvalue) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (!g_cache) return JNI_FALSE;

    std::string key = JStringToStdString(env, jkey);

    jsize len = env->GetArrayLength(jvalue);
    std::vector<uint8_t> value(len);
    env->GetByteArrayRegion(jvalue, 0, len, reinterpret_cast<jbyte*>(value.data()));

    bool ok = g_cache->update(key, value);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_site_ycsb_db_cachelib_CacheLibClient_nativeDelete
  (JNIEnv* env, jobject, jstring, jstring jkey) {
    std::lock_guard<std::mutex> lock(g_cache_mutex);
    if (!g_cache) return JNI_FALSE;

    std::string key = JStringToStdString(env, jkey);
    bool ok = g_cache->remove(key);
    return ok ? JNI_TRUE : JNI_FALSE;
}