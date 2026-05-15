import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["newRows"]

  add() {
    const key = prompt("Attribute name?")
    if (!key) return
    const wrap = document.createElement("div")
    wrap.className = "flex gap-2 mb-1"
    wrap.innerHTML =
      `<span class="w-32">${key}</span>` +
      `<input type="text" name="contact[additional_attributes][${key}]" class="input">` +
      `<button type="button" data-action="kv-attrs#removeNew">Remove</button>`
    this.newRowsTarget.appendChild(wrap)
  }

  remove(e) {
    const key = e.currentTarget.dataset.key
    const hidden = document.createElement("input")
    hidden.type = "hidden"
    hidden.name = `contact[additional_attributes][${key}]`
    hidden.value = ""
    e.currentTarget.parentElement.replaceWith(hidden)
  }

  removeNew(e) {
    e.currentTarget.parentElement.remove()
  }
}
