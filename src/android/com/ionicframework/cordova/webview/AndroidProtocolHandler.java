package com.ionicframework.cordova.webview;

// Copyright 2012 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import android.content.Context;
import android.content.res.AssetManager;
import android.net.Uri;
import android.util.Log;
import android.util.TypedValue;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;


public class AndroidProtocolHandler {
  private static final String TAG = "AndroidProtocolHandler";

  private Context context;
  private final Map<String, byte[]> memoryBackedAssetCache;
  private final Set<String> memoryCachedAssetExtensions;

  public AndroidProtocolHandler(Context context) {
    this(context, Collections.<String>emptySet());
  }

  public AndroidProtocolHandler(Context context, Set<String> memoryCachedAssetExtensions) {
    this.context = context;
    this.memoryBackedAssetCache = new ConcurrentHashMap<String, byte[]>();
    if (memoryCachedAssetExtensions == null) {
      this.memoryCachedAssetExtensions = Collections.<String>emptySet();
    } else {
      this.memoryCachedAssetExtensions = memoryCachedAssetExtensions;
    }
  }

  public InputStream openAsset(String path) throws IOException {
    if (shouldServeFromMemory(path)) {
      InputStream cached = openMemoryBackedAsset(path);
      if (cached != null) {
        return cached;
      }
    }
    return context.getAssets().open(path, AssetManager.ACCESS_STREAMING);
  }

  public InputStream openResource(Uri uri) {
    assert uri.getPath() != null;
    // The path must be of the form ".../asset_type/asset_name.ext".
    List<String> pathSegments = uri.getPathSegments();
    String assetType = pathSegments.get(pathSegments.size() - 2);
    String assetName = pathSegments.get(pathSegments.size() - 1);

    // Drop the file extension.
    assetName = assetName.split("\\.")[0];
    try {
      // Use the application context for resolving the resource package name so that we do
      // not use the browser's own resources. Note that if 'context' here belongs to the
      // test suite, it does not have a separate application context. In that case we use
      // the original context object directly.
      if (context.getApplicationContext() != null) {
        context = context.getApplicationContext();
      }
      int fieldId = getFieldId(context, assetType, assetName);
      int valueType = getValueType(context, fieldId);
      if (valueType == TypedValue.TYPE_STRING) {
        return context.getResources().openRawResource(fieldId);
      } else {
        Log.e(TAG, "Asset not of type string: " + uri);
        return null;
      }
    } catch (ClassNotFoundException e) {
      Log.e(TAG, "Unable to open resource URL: " + uri, e);
      return null;
    } catch (NoSuchFieldException e) {
      Log.e(TAG, "Unable to open resource URL: " + uri, e);
      return null;
    } catch (IllegalAccessException e) {
      Log.e(TAG, "Unable to open resource URL: " + uri, e);
      return null;
    }
  }

  public InputStream openFile(String filePath) throws IOException  {
    String realPath = filePath.replace(WebViewLocalServer.fileStart, "");
    File localFile = new File(realPath);
    return new FileInputStream(localFile);
  }

  public InputStream openContentUrl(Uri uri)  throws IOException {
    Integer port = uri.getPort();
    String realPath;
    if (port == -1) {
      realPath = uri.toString().replace(uri.getScheme() + "://" + uri.getHost() + WebViewLocalServer.contentStart, "content:/");
    } else {
      realPath = uri.toString().replace(uri.getScheme() + "://" + uri.getHost() + ":" + port + WebViewLocalServer.contentStart, "content:/");
    }
    InputStream stream = null;
    try {
      stream = context.getContentResolver().openInputStream(Uri.parse(realPath));
    } catch (SecurityException e) {
      Log.e(TAG, "Unable to open content URL: " + uri, e);
    }
    return stream;
  }

  private static int getFieldId(Context context, String assetType, String assetName)
    throws ClassNotFoundException, NoSuchFieldException, IllegalAccessException {
    Class<?> d = context.getClassLoader()
      .loadClass(context.getPackageName() + ".R$" + assetType);
    java.lang.reflect.Field field = d.getField(assetName);
    int id = field.getInt(null);
    return id;
  }

  private static int getValueType(Context context, int fieldId) {
    TypedValue value = new TypedValue();
    context.getResources().getValue(fieldId, value, true);
    return value.type;
  }

  private boolean shouldServeFromMemory(String path) {
    if (memoryCachedAssetExtensions == null || memoryCachedAssetExtensions.isEmpty() || path == null) {
      return false;
    }
    for (String extension : memoryCachedAssetExtensions) {
      if (extension != null && path.endsWith(extension)) {
        return true;
      }
    }
    return false;
  }

  private InputStream openMemoryBackedAsset(String path) {
    try {
      byte[] cached = memoryBackedAssetCache.get(path);
      if (cached == null) {
        cached = readAssetIntoMemory(path);
        if (cached != null) {
          memoryBackedAssetCache.put(path, cached);
        }
      }
      if (cached == null) {
        return null;
      }
      return new ByteArrayInputStream(cached);
    } catch (IOException e) {
      Log.e(TAG, "Unable to cache asset in memory: " + path, e);
      return null;
    }
  }

  private byte[] readAssetIntoMemory(String path) throws IOException {
    AssetManager manager = context.getAssets();
    InputStream assetStream = null;
    ByteArrayOutputStream buffer = null;
    try {
      assetStream = manager.open(path, AssetManager.ACCESS_STREAMING);
      buffer = new ByteArrayOutputStream();
      byte[] temp = new byte[16 * 1024];
      int read;
      while ((read = assetStream.read(temp)) != -1) {
        buffer.write(temp, 0, read);
      }
      return buffer.toByteArray();
    } finally {
      if (assetStream != null) {
        try {
          assetStream.close();
        } catch (IOException ignored) {
        }
      }
      if (buffer != null) {
        try {
          buffer.close();
        } catch (IOException ignored) {
        }
      }
    }
  }
}
