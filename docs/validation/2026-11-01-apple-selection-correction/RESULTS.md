# Algorithm UI correction — November 1, 2026

Removed the added Allow Estimated Input Power switch, its setters, and its localization keys. The pre-existing Apple-selection warning remains, but it is gated by SpringBoard's confirmed missing-input recommendation. Confirmed measured support and unknown availability do not trigger that warning. No OS-version cutoff was introduced.

The rootful, rootless, and RootHide release packages were rebuilt and installed on 14.8, 16.3.1, 16.7.16, and 26.0. Package inspection confirms that the added switch text and selectors are absent in every variant. The 39 availability and 96 Stack/estimator host checks passed with sanitizers.

Fresh native preference hosts on 16.3.1, 16.7.16, and 26.0 passed these checks:

- No additional approximation toggle is present.
- Selecting Jikan clears approximation consent.
- Selecting Apple shows no approximation warning on these confirmed-support devices.
- Apple is selected and approximation remains disabled.
- The actual displayed controller and its rendered footer report no enabled approximation.

Visual review caught an initially stale enabled-approximation footer after consent was cleared. The Algorithm controller now observes preference reloads as well as availability changes, and the rendered-footer assertion passes on all three UI test devices.

Both iOS 16 devices were left with approximation disabled, as requested. Other preferences were preserved, including the iPhone 8's disabled state. The earlier device run captured native Apple inference on 16.3.1 and SMC-backed Apple inference on 16.7.16 without needing approximation. The corrected helper path remains in place.

The 26.0 UI was tested in the existing TweakSettings host. The iOS 14 package was updated and inspected, but its UI was not re-instrumented in this correction run. The historical test report in the neighboring apple-availability directory describes the superseded toggle build and is marked accordingly.

The earlier iOS 16.3.1 rejection was not reproduced, so its original missing input is still unknown. These changes do not claim that only iOS 14 can ever lack required inputs; they preserve the actual measured-support results of the tested devices.

No commits were made. See results.json and the native Algorithm captures in this directory.
