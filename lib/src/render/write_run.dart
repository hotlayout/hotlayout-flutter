/// What a press does with a write action (`setValue`, `toggleValue`): the step the rule found, performed through
/// the write the fields use.
library;

import '../report/report_hub.dart';

import '../model/write_action.dart';
import 'host_callbacks.dart';

/// Performs [step]: a value goes through [write] (session and host, at the same moment), the same value again
/// goes nowhere, an unusable action or a path the write gate refuses writes nothing and is named in the debug log.
/// The action never reaches the host as an action.
void runWriteStep(WriteStep step, {required SduiValueWrite write}) {
  switch (step) {
    case WriteNow(:final path, :final value):
      if (isWritablePath(path)) {
        write(path, value);
      } else {
        ReportHub.ignored('write path "${_clip(path)}"', 'not a writable path: nothing was written');
      }
    case WriteSame():
      break;
    case WriteInvalid(:final problem):
      ReportHub.ignored('write action', 'does nothing: ${problem.wire}');
  }
}

String _clip(String path) => path.length > 80 ? path.substring(0, 80) : path;
