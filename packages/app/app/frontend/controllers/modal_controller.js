import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["userSelect"]

  async refreshUsers(e) {
    const select = this.element.querySelector("select[name='transfer[to_team_id]']")
    const url = new URL(select.dataset.modalUsersUrl, window.location.origin)
    url.searchParams.set("to_team_id", e.target.value)
    const res = await fetch(url, { headers: { Accept: "application/json" } })
    const { users } = await res.json()
    this.userSelectTarget.innerHTML =
      "<option value=''>— unassigned —</option>" +
      users.map((u) => `<option value="${u.id}">${u.name}</option>`).join("")
  }

  close() {
    this.element.remove()
  }
}
