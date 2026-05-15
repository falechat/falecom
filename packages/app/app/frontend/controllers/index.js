// Eagerly register Stimulus controllers. JR's controllers (if any) are
// registered here once copied; app controllers follow the Stimulus
// `<name>_controller.js` convention.
import { application } from "./application";

import KvAttrsController from "./kv_attrs_controller";
application.register("kv-attrs", KvAttrsController);

import NodeTypeSwapController from "./node_type_swap_controller";
application.register("node-type-swap", NodeTypeSwapController);

export { application };
