import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// True only while startup auto-config is still trying to restore and
/// configure an existing sync session on a freshly created handle.
final syncAutoConfigureInProgress = ValueNotifier<bool>(false);

/// Current handle for repository instances built before provider rebuilds.
final syncCurrentHandle = ValueNotifier<ffi.PrismSyncHandle?>(null);

/// True once persisted sync-group credentials exist (the keychain `sync_id` /
/// `device_id` / `device_secret` slots `_autoConfigureIfReady` reads). Gates
/// the durable-outbox enqueue: a never-paired device enqueues nothing
/// (`bootstrapExistingData` seeds the whole store at sync setup), bounding
/// outbox growth to actually-paired installs. Set when a handle is created on
/// a device with stored credentials and at first-device setup completion;
/// cleared when credentials are wiped (unpair / reset).
///
/// Narrow startup window: this defaults to false and only flips true once boot
/// reaches the handle-create path. A write that committed on a paired device
/// BEFORE that point would no-op its enqueue (a drop). Low risk — the data
/// layer is not interactive that early in boot — so a documented limitation
/// rather than a guard.
final syncCredentialsPersisted = ValueNotifier<bool>(false);
