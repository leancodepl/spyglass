import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spyglass/flutter_spyglass.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  // Lets an MCP client (e.g. marionette_mcp) inspect and drive this app at
  // runtime - inert in release builds.
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MainApp());
}

/// The data collected across every step of the wizard.
///
/// One instance is shared by all three step screens for the duration of a
/// single wizard run - see [WizardScope].
class WizardData extends ChangeNotifier {
  WizardData() {
    debugPrint('WizardData created (#$hashCode)');
  }

  String name = '';
  String email = '';
  String plan = plans.first;

  void updateName(String value) {
    name = value;
    notifyListeners();
  }

  void updateEmail(String value) {
    email = value;
    notifyListeners();
  }

  void updatePlan(String value) {
    plan = value;
    notifyListeners();
  }

  static const plans = ['Basic', 'Pro', 'Enterprise'];

  @override
  void dispose() {
    debugPrint('WizardData disposed (#$hashCode)');
    super.dispose();
  }
}

/// Every dependency a wizard run needs, registered as one unit by each step
/// screen's [WizardScope] - see [DepsProvider.register].
final wizardModule = Module([
  ChangeNotifierDependency<WizardData>((_, __) => WizardData()),
], debugLabel: 'wizard');

/// Wraps a wizard step's screen with a [DepsProvider] sharing [flowId]: the
/// first step screen pushed for a given [flowId] creates [WizardData], every
/// later one reuses the same instance, and it's disposed once the last of
/// them - however the user got there, forward or back - unmounts. Without
/// this, either every step would get its own throwaway [WizardData], or
/// something above the wizard entirely (outliving it) would need to own and
/// manually dispose of one instead.
class WizardScope extends StatelessWidget {
  const WizardScope({super.key, required this.flowId, required this.child});

  /// Identifies one run of the wizard - shared by every step pushed for it,
  /// distinct from any other run (e.g. if the user starts the wizard again
  /// after finishing or cancelling it).
  final Object flowId;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DepsProvider.shared(
      flowId,
      register: [wizardModule],
      child: child,
    );
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared DepsProvider demo')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // A fresh identity per run, so starting the wizard twice (e.g.
            // after finishing once) never shares data between runs.
            final flowId = UniqueKey();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StepOneScreen(flowId: flowId),
              ),
            );
          },
          child: const Text('Start wizard'),
        ),
      ),
    );
  }
}

class StepOneScreen extends StatelessWidget {
  const StepOneScreen({super.key, required this.flowId});

  final Object flowId;

  @override
  Widget build(BuildContext context) {
    return WizardScope(
      flowId: flowId,
      child: Builder(
        builder: (context) {
          final data = context.get<WizardData>();
          return Scaffold(
            appBar: AppBar(title: const Text('Step 1 of 3 · About you')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: data.name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: data.updateName,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: data.email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    onChanged: data.updateEmail,
                  ),
                  const SizedBox(height: 24),
                  const SharedScopeLabel(),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StepTwoScreen(flowId: flowId),
                      ),
                    ),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class StepTwoScreen extends StatelessWidget {
  const StepTwoScreen({super.key, required this.flowId});

  final Object flowId;

  @override
  Widget build(BuildContext context) {
    return WizardScope(
      flowId: flowId,
      child: Builder(
        builder: (context) {
          // Watched (rather than just read, like the other steps) so the
          // radio tiles below reflect a plan choice made on an earlier visit
          // to this same step.
          final data = context.watch<WizardData>();
          return Scaffold(
            appBar: AppBar(title: const Text('Step 2 of 3 · Choose a plan')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: RadioGroup<String>(
                groupValue: data.plan,
                onChanged: (value) => data.updatePlan(value!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final plan in WizardData.plans)
                      RadioListTile<String>(title: Text(plan), value: plan),
                    const SizedBox(height: 8),
                    const SharedScopeLabel(),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StepThreeScreen(flowId: flowId),
                        ),
                      ),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class StepThreeScreen extends StatelessWidget {
  const StepThreeScreen({super.key, required this.flowId});

  final Object flowId;

  @override
  Widget build(BuildContext context) {
    return WizardScope(
      flowId: flowId,
      child: Builder(
        builder: (context) {
          final data = context.get<WizardData>();
          return Scaffold(
            appBar: AppBar(title: const Text('Step 3 of 3 · Review')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Name: ${data.name}'),
                  Text('Email: ${data.email}'),
                  Text('Plan: ${data.plan}'),
                  const SizedBox(height: 24),
                  const SharedScopeLabel(),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Submitted for ${data.name}! Check the console '
                            'for the "WizardData disposed" log as every '
                            'wizard screen unwinds.',
                          ),
                        ),
                      );
                      // Pops all three step screens in one go - the last of
                      // them to unmount is what triggers WizardData's
                      // disposal, not this button press itself.
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shows the identity of the shared scope and its [WizardData] so you can
/// see, step to step (and back), that they're the exact same instances -
/// and, via the console logs in [WizardData], that a new run gets fresh
/// ones while an old run's are disposed exactly once, when its last step
/// screen goes away.
class SharedScopeLabel extends StatelessWidget {
  const SharedScopeLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.get<WizardData>();
    return Text(
      'Shared Deps scope #${identityHashCode(context.deps)} · '
      'WizardData #${identityHashCode(data)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
