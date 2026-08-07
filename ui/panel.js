const $roomId    = document.getElementById("room-id");
const $list      = document.getElementById("list");
const $empty     = document.getElementById("empty");
const $addForm   = document.getElementById("add-form");
const $addName   = document.getElementById("add-name");
const $addButton = document.getElementById("add-button");

let currentRoomId = null;

function renderRoom() {
  if (currentRoomId) {
    $roomId.textContent = currentRoomId;
    $roomId.classList.remove("unknown");
    $addButton.disabled = false;
  } else {
    $roomId.textContent = "unknown";
    $roomId.classList.add("unknown");
    $addButton.disabled = true;
  }
}

function renderList(blorps) {
  $list.innerHTML = "";
  if (!blorps || blorps.length === 0) {
    $empty.hidden = false;
    return;
  }
  $empty.hidden = true;
  for (const b of blorps) {
    const li = document.createElement("li");

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = b.name;

    const roomId = document.createElement("span");
    roomId.className = "room-id";
    roomId.textContent = b.room_id;

    const remove = document.createElement("button");
    remove.className = "remove";
    remove.type = "button";
    remove.textContent = "×";
    remove.addEventListener("click", () => panel.post("remove", { name: b.name }));

    li.appendChild(name);
    li.appendChild(roomId);
    li.appendChild(remove);
    $list.appendChild(li);
  }
}

panel.on("blorps_list", (frame) => renderList(frame.blorps || []));

panel.on("room_changed", (frame) => {
  currentRoomId = frame.room_id || null;
  renderRoom();
});

$addForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $addName.value.trim();
  if (!name || !currentRoomId) return;
  panel.post("add", { name });
  $addName.value = "";
});

renderRoom();

panel.post("ready", {});
