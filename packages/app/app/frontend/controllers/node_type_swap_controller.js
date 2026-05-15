import { Controller } from "@hotwired/stimulus"

// Shows the fields partial matching the selected node_type, hides others.
// Disables hidden textareas so only the active one submits a `content` param.
export default class extends Controller {
  static targets = ["select", "fields"]

  connect() { this.swap() }

  swap() {
    const type = this.selectTarget.value
    this.fieldsTargets.forEach((el) => {
      const match = el.dataset.type === type
      el.style.display = match ? "" : "none"
      el.querySelectorAll("textarea, input, select").forEach((field) => {
        if (field.name === "flow_node[node_type]") return
        field.disabled = !match
      })
    })
  }
}
