const $count     = document.getElementById("count");
const $roomName  = document.getElementById("room-name");
const $filter    = document.getElementById("filter");
const $list      = document.getElementById("list");
const $empty     = document.getElementById("empty");
const $addForm   = document.getElementById("add-form");
const $addName   = document.getElementById("add-name");
const $addButton = document.getElementById("add-button");

let currentRoomId   = null;
let currentRoomName = null;
let allBlorps       = [];

function renderRoom() {
  if (currentRoomId) {
    $roomName.textContent = currentRoomName || currentRoomId;
    $roomName.classList.remove("unknown");
    $addButton.disabled = false;
  } else {
    $roomName.textContent = "unknown";
    $roomName.classList.add("unknown");
    $addButton.disabled = true;
  }
}

function matchesFilter(b, query) {
  if (!query) return true;
  const q = query.toLowerCase();
  return b.name.toLowerCase().includes(q) || (b.room_name || "").toLowerCase().includes(q);
}

function render() {
  $count.textContent = allBlorps.length;

  const query = $filter.value.trim();
  const visible = allBlorps.filter((b) => matchesFilter(b, query));

  $list.innerHTML = "";
  if (visible.length === 0) {
    $empty.textContent = allBlorps.length === 0
      ? "No blorps registered."
      : `No blorps match "${query}".`;
    $empty.hidden = false;
    return;
  }
  $empty.hidden = true;
  for (const b of visible) {
    const li = document.createElement("li");

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = b.name;

    const roomName = document.createElement("span");
    roomName.className = "room-name";
    roomName.textContent = b.room_name || "(unknown room)";

    const remove = document.createElement("button");
    remove.className = "remove";
    remove.type = "button";
    remove.textContent = "×";
    remove.addEventListener("click", () => panel.post("remove", { name: b.name }));

    li.appendChild(name);
    li.appendChild(roomName);
    li.appendChild(remove);
    $list.appendChild(li);
  }
}

panel.on("blorps_list", (frame) => {
  allBlorps = frame.blorps || [];
  render();
});

panel.on("room_changed", (frame) => {
  currentRoomId = frame.room_id || null;
  currentRoomName = frame.room_name || null;
  renderRoom();
});

$filter.addEventListener("input", render);

$addForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $addName.value.trim();
  if (!name || !currentRoomId) return;
  panel.post("add", { name });
  $addName.value = "";
});

renderRoom();
render();

panel.post("ready", {});
