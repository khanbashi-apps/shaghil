import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let emoji: String
    let color: String
    let files: [(String, String)]

    static let all: [ProjectTemplate] = [counter, todo, today, blank]

    static let counter = ProjectTemplate(
        id: "counter", title: "عدّاد", subtitle: "يتزامن مع الويدجت الكبير", icon: "plusminus.circle", emoji: "📿", color: "#2F9E74",
        files: [("index.html", """
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>عدّادي</title>
<style>
  :root { color-scheme: light dark; --a: #2F9E74; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: -apple-system, system-ui; }
  .n { font-size: 96px; font-weight: 800; font-variant-numeric: tabular-nums; text-align: center; }
  .row { display: flex; gap: 14px; justify-content: center; margin-top: 18px; }
  button { font-size: 30px; width: 76px; height: 76px; border-radius: 50%; border: 0; background: var(--a); color: #fff; }
  button.s { background: rgba(127,127,127,.2); color: inherit; font-size: 16px; width: auto; padding: 0 18px; border-radius: 38px; }
</style>
</head>
<body>
  <div>
    <div class="n" id="n">0</div>
    <div class="row">
      <button onclick="add(-1)">−</button>
      <button onclick="add(1)">+</button>
    </div>
    <div class="row"><button class="s" onclick="reset()">تصفير</button></div>
  </div>
<script>
  // يقرأ آخر قيمة (من التخزين المحلي أو من أزرار الويدجت)
  const fromWidget = window.shaghil && shaghil.state && shaghil.state.counter;
  let n = Number(fromWidget ?? localStorage.getItem('count') ?? 0);
  function render() {
    document.getElementById('n').textContent = n;
    localStorage.setItem('count', n);
    // يرسل القيمة إلى ويدجت الشاشة الرئيسية
    if (window.shaghil) shaghil.widget({ title: 'عدّادي', counter: n, step: 1 });
  }
  function add(d) { n += d; render(); }
  function reset() { n = 0; render(); }
  render();
  console.log('العدّاد جاهز', n);
</script>
</body>
</html>
""")])

    static let todo = ProjectTemplate(
        id: "todo", title: "مهامي", subtitle: "قائمة مهام تظهر في الويدجت", icon: "checklist", emoji: "🗒️", color: "#2F7BEF",
        files: [("index.html", """
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>مهامي</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>مهامي</h1>
  <form id="f"><input id="t" placeholder="مهمة جديدة…" autocomplete="off"><button>إضافة</button></form>
  <ul id="list"></ul>
  <script src="app.js"></script>
</body>
</html>
"""), ("style.css", """
:root { color-scheme: light dark; --a: #2F7BEF; }
body { font-family: -apple-system, system-ui; margin: 0; padding: 20px; padding-top: max(20px, env(safe-area-inset-top)); }
h1 { margin: 0 0 14px; }
form { display: flex; gap: 8px; }
input { flex: 1; font-size: 17px; padding: 12px; border-radius: 12px; border: 1px solid rgba(127,127,127,.3); background: transparent; color: inherit; }
button { font-size: 16px; padding: 0 16px; border-radius: 12px; border: 0; background: var(--a); color: #fff; }
ul { list-style: none; padding: 0; }
li { display: flex; align-items: center; gap: 10px; padding: 14px 4px; border-bottom: 1px solid rgba(127,127,127,.2); font-size: 17px; }
li.done span { text-decoration: line-through; opacity: .5; }
li .x { margin-inline-start: auto; background: none; color: #e5484d; font-size: 20px; padding: 0 6px; }
"""), ("app.js", """
// قائمة مهام بسيطة تُحفظ محلياً وتظهر في ويدجت «شغّل» الكبير
let items = JSON.parse(localStorage.getItem('items') || '[]');

// إذا علّمت مهمة من الويدجت، نأخذ حالتها من هناك
const w = window.shaghil && shaghil.state;
if (w && Array.isArray(w.items) && w.items.length === items.length) {
  items = items.map((it, i) => ({ ...it, done: w.items[i].done }));
}

const list = document.getElementById('list');

function save() {
  localStorage.setItem('items', JSON.stringify(items));
  const left = items.filter(i => !i.done).length;
  if (window.shaghil) shaghil.widget({ title: 'مهامي', value: left + ' متبقية', items: items });
}

function render() {
  list.innerHTML = '';
  items.forEach((it, i) => {
    const li = document.createElement('li');
    li.className = it.done ? 'done' : '';
    li.innerHTML = `<input type="checkbox" ${it.done ? 'checked' : ''}><span></span><button class="x">×</button>`;
    li.querySelector('span').textContent = it.text;
    li.querySelector('input').onchange = () => { it.done = !it.done; save(); render(); };
    li.querySelector('.x').onclick = () => { items.splice(i, 1); save(); render(); };
    list.appendChild(li);
  });
}

document.getElementById('f').onsubmit = (e) => {
  e.preventDefault();
  const t = document.getElementById('t');
  if (!t.value.trim()) return;
  items.push({ text: t.value.trim(), done: false });
  t.value = '';
  save(); render();
};

save(); render();
""")])

    static let today = ProjectTemplate(
        id: "today", title: "بطاقة اليوم", subtitle: "ويدجت حي يتحدّث بنفسه (widget.js)", icon: "calendar", emoji: "☀️", color: "#E0A100",
        files: [("index.html", """
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>بطاقة اليوم</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, system-ui; display: grid; place-items: center; min-height: 100vh; margin: 0; text-align: center; }
  .d { font-size: 64px; font-weight: 800; } .s { opacity: .6; font-size: 20px; }
</style>
</head>
<body>
  <div><div class="d" id="d"></div><div class="s" id="s"></div><p class="s">الويدجت يقرأ الملف widget.js ويحدّث نفسه كل ربع ساعة.</p></div>
  <script src="widget.js"></script>
  <script>
    const r = widget({});
    document.getElementById('d').textContent = r.value;
    document.getElementById('s').textContent = r.subtitle;
  </script>
</body>
</html>
"""), ("widget.js", """
// هذه الدالة يشغّلها الويدجت نفسه على الشاشة الرئيسية (بدون فتح التطبيق)
// أعد كائناً فيه: title و value و subtitle و items (اختياري)
function widget(state) {
  const now = new Date();
  const day = now.toLocaleDateString('ar', { weekday: 'long' });
  const date = now.toLocaleDateString('ar', { day: 'numeric', month: 'long' });
  const end = new Date(now.getFullYear(), 11, 31);
  const left = Math.ceil((end - now) / 86400000);
  return {
    title: 'اليوم',
    value: day,
    subtitle: date,
    items: [
      { text: 'باقي على نهاية السنة ' + left + ' يوم', done: false },
      { text: 'الساعة ' + now.toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' }), done: false }
    ]
  };
}
""")])

    static let blank = ProjectTemplate(
        id: "blank", title: "صفحة فارغة", subtitle: "HTML + CSS + JS", icon: "doc", emoji: "⚡️", color: "#6340DC",
        files: [("index.html", """
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>صفحتي</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>مرحباً 👋</h1>
  <script src="script.js"></script>
</body>
</html>
"""), ("style.css", """
:root { color-scheme: light dark; }
body { font-family: -apple-system, system-ui; padding: 24px; }
"""), ("script.js", """
console.log('جاهز!');
""")])

    @discardableResult
    func make(in store: ProjectStore) -> Project {
        var p = store.create(code: files[0].1, name: title, language: CodeLanguage.from(fileName: files[0].0))
        // rename main file if needed and add the rest
        if p.files.first != files[0].0 {
            _ = store.renameFile(p.files[0], to: files[0].0, in: p.id)
        }
        for (name, content) in files.dropFirst() {
            _ = store.addFile(name, content: content, to: p.id)
        }
        store.setIcon(p.id, emoji: emoji, colorHex: color)
        store.setActiveFile(files[0].0, in: p.id)
        p = store.project(p.id) ?? p
        return p
    }
}
