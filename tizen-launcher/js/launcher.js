var KEY = { LEFT:37, UP:38, RIGHT:39, DOWN:40, ENTER:13, BACK:10009 };
var pos = { r:0, c:0 };
var rowEls = [];

function build() {
  var root = document.getElementById("rows");
  ROWS.forEach(function (row) {
    var t = document.createElement("div");
    t.className = "row-title";
    t.textContent = row.title;
    var el = document.createElement("div");
    el.className = "row";
    var tiles = row.items.map(function (item) {
      var d = document.createElement("div");
      d.className = "tile";
      d.textContent = item.name;
      d.style.background = "linear-gradient(135deg," + item.color + "55, var(--card))";
      el.appendChild(d);
      return d;
    });
    root.appendChild(t);
    root.appendChild(el);
    rowEls.push(tiles);
  });
  focus();
}

function focus() {
  rowEls.forEach(function (r) { r.forEach(function (t) { t.classList.remove("focus"); }); });
  rowEls[pos.r][pos.c].classList.add("focus");
}

function launch() {
  var item = ROWS[pos.r].items[pos.c];
  try {
    tizen.application.launch(item.id, null, function (e) {
      console.log("launch failed: " + item.name + " " + e.message);
    });
  } catch (e) { console.log("tizen API unavailable: " + e.message); }
}

document.addEventListener("keydown", function (e) {
  var rows = ROWS.length;
  switch (e.keyCode) {
    case KEY.LEFT:  pos.c = Math.max(0, pos.c - 1); break;
    case KEY.RIGHT: pos.c = Math.min(ROWS[pos.r].items.length - 1, pos.c + 1); break;
    case KEY.UP:    pos.r = Math.max(0, pos.r - 1); break;
    case KEY.DOWN:  pos.r = Math.min(rows - 1, pos.r + 1); break;
    case KEY.ENTER: launch(); return;
    case KEY.BACK:
      try { tizen.application.getCurrentApplication().exit(); } catch (x) {}
      return;
  }
  pos.c = Math.min(pos.c, ROWS[pos.r].items.length - 1);
  focus();
});

function tick() {
  var d = new Date();
  document.getElementById("clock").textContent =
    d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
setInterval(tick, 10000); tick();
try { tizen.tvinputdevice.registerKey("Back"); } catch (e) {}
build();
