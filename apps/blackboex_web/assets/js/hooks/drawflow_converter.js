/**
 * @file Compatibility exports for Drawflow and BlackboexFlow conversion helpers.
 *
 * Older hook tests import the converter through `js/hooks/drawflow_converter`;
 * production hook wiring uses the implementation under `js/lib/flow`.
 */
export {
  blackboexToDrawflow,
  drawflowToBlackboex,
} from "../lib/flow/drawflow_converter";
