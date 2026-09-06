// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$showSyncButtonProviderHash() =>
    r'88750426c636f2429bf7563f274fa5b06be6d647';

/// See also [showSyncButtonProvider].
@ProviderFor(showSyncButtonProvider)
final showSyncButtonProviderProvider = AutoDisposeProvider<bool>.internal(
  showSyncButtonProvider,
  name: r'showSyncButtonProviderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$showSyncButtonProviderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShowSyncButtonProviderRef = AutoDisposeProviderRef<bool>;
String _$userHash() => r'af53d2ff18bc7a560b862007a0f3ef8806e0afa2';

/// See also [User].
@ProviderFor(User)
final userProvider = NotifierProvider<User, AccountModel?>.internal(
  User.new,
  name: r'userProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$userHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$User = Notifier<AccountModel?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
