// Eagerly register Stimulus controllers. JR's controllers (if any) are
// registered here once copied; app controllers follow the Stimulus
// `<name>_controller.js` convention.
import { application } from "./application";

// Example pattern — uncomment to register the JR controllers you copy:
// import NavbarController from "./navbar_controller";
// application.register("navbar", NavbarController);

export { application };
