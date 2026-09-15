# flutter_shared_deps_provider

Demonstrates `DepsProvider.sharedKey`: a three-step wizard ("About you" →
"Choose a plan" → "Review") where each step is pushed as its own route, but
all three share one `WizardData` instance for the run - created when the
first step screen mounts, disposed once the last one unmounts, regardless of
how the user gets there (forward, back, or submitting from the last step).

See `lib/main.dart`, in particular `WizardScope`, which wraps each step's
screen in a `DepsProvider(sharedKey: flowId, register: [wizardModule], ...)`.

Run it and watch the console: `WizardData created` prints once when step 1
first mounts, and `WizardData disposed` prints once - only after the last
step screen for that run is gone, e.g. once you submit from step 3 (which
pops the whole wizard) or back out of step 1 entirely. Each step also shows
the shared scope's and `WizardData`'s identity hash codes, so you can confirm
they're the exact same instances step to step (and after navigating back).
