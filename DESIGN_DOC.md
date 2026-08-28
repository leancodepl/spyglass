# Design doc

This document describes the guiding principles and requirements for the
implementation of Spyglass packages.

## General ideas

- Spyglass solves dependency injection (DI) for Flutter and pure Dart (terminal,
  server etc.) applications.
- It should be easy to adopt for current
  [provider](https://pub.dev/packages/provider) and
  [get_it](https://pub.dev/packages/get_it) users.
- The core idea is to have containers (Deps class) one can place services in,
  and then obtain them in any place of the app.
- The containers can be scoped, i.e. access to and lifetime of some services can
  be restricted to some parts of the app.
- Implementation has to be performant, i.e. at least in the same performance
  class as provider and get_it.

## Base implementation

- Services need to be able to be registered without a Flutter app running.
- Scoped containers form a tree hierarchy and inherit services registered in
  their ancestors.
- One can react to services being registered, unregistered, and most of all
  changed.
- Changes in ancestor scopes (new services registered, unregistered or changed)
  propagate down the tree.
- One can optionally observe changes to services' internal state, akin to
  provider.
- One service can be registered multiple times, as its class or (optionally) any
  of its superclasses/implemented interfaces.
- A service can be updated or reinstantiated in response to some of its
  dependencies chaning.
- The implementation provides debugging information in a dedicated diagnostics
  mode, opt-in for profile and release builds and opt-out for debug builds.

## Flutter integration

- Provides API familiar to developers using provider.
- Provides optional bloc binding similar to
  [flutter_bloc](https://pub.dev/packages/flutter_bloc)
- Implements the Diagnosticable interface for easier debugging
- (lower priority) Build diagnostics mode and devtools for inspecting spyglass
  state
- It should be possible to bind dependency scopes to widget subtrees, especially
  pages/routes and collections of pages/routes representing a process.

## Testing

- Benchmarks comparing flutter_spyglass to provider

## Extras

- Write AI skills for migrating from provider to flutter_spyglass
