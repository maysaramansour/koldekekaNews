/* ── State ─────────────────────────────────────────────────────────────────── */
const state = {
  articles:      new Map(),   // id → article (all fetched)
  renderedIds:   new Set(),   // ids currently in the DOM grid
  lastFetch:     0,
  activeSource:  'all',       // source filter
  activeLang:    'all',       // 'all' | 'ar' | 'en'
  activeUrgent:  false,       // urgency filter
  countdownId:   null,
  toastTimer:    null,
  nextIn:        60,
  initialized:   false,
  // Pagination
  currentPage:   1,
  hasMore:       false,
  loadingMore:   false,
};

/* ── DOM refs ──────────────────────────────────────────────────────────────── */
const $grid         = document.getElementById('newsGrid');
const $liveDot      = document.getElementById('liveDot');
const $statusLbl    = document.getElementById('statusLabel');
const $count        = document.getElementById('articleCount');
const $nextUpd      = document.getElementById('nextUpdate');
const $filterBar    = document.getElementById('filterBar');
const $toast        = document.getElementById('toast');
const $notifBell    = document.getElementById('notifBell');
const $notifBadge   = document.getElementById('notifBadge');
const $notifPanel   = document.getElementById('notifPanel');
const $notifList    = document.getElementById('notifList');
const $notifClear   = document.getElementById('notifClear');
const $overlay      = document.getElementById('modalOverlay');
const $modalClose   = document.getElementById('modalClose');
const $modalLoading = document.getElementById('modalLoading');
const $modalContent = document.getElementById('modalContent');
const $modalError   = document.getElementById('modalError');
const $modalHero    = document.getElementById('modalHero');
const $modalMeta    = document.getElementById('modalMeta');
const $modalTitle   = document.getElementById('modalTitle');
const $modalDesc    = document.getElementById('modalDesc');
const $modalBody    = document.getElementById('modalArticleBody');
const $modalReadBtn = document.getElementById('modalReadBtn');
const $modalErrBtn  = document.getElementById('modalErrorBtn');
const $modalErrMsg  = document.getElementById('modalErrorMsg');

/* ── Helpers ───────────────────────────────────────────────────────────────── */
const INTERVAL_SEC = 60;

function timeAgo(date) {
  const d   = date instanceof Date ? date : new Date(date);
  const sec = Math.max(0, Math.floor((Date.now() - d) / 1000));
  if (sec < 60)    return `الآن`;
  if (sec < 3600)  return `${Math.floor(sec / 60)}د`;
  if (sec < 86400) return `${Math.floor(sec / 3600)}س`;
  return d.toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' });
}

function showToast(msg) {
  $toast.textContent = msg;
  $toast.classList.add('show');
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => $toast.classList.remove('show'), 3500);
}

/* ── Browser Notifications ─────────────────────────────────────────────────── */
async function requestNotifPermission() {
  if (!('Notification' in window)) return;
  if (Notification.permission === 'default') await Notification.requestPermission();
}

function pushNotification(articles) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  // Pick the most urgent article (highest score), or first
  const top = articles.reduce((best, a) =>
    urgencyScore(a.title) > urgencyScore(best.title) ? a : best, articles[0]);
  const count = articles.length;
  const body  = count > 1
    ? `${top.title}\n+${count - 1} أخبار أخرى`
    : top.title;
  const notif = new Notification('كل دقيقة — خبر جديد', {
    body,
    icon:  top.image && !top.aiImage ? top.image : undefined,
    badge: '/favicon.ico',
    tag:   'akhbar-update',   // replaces previous notification instead of stacking
    renotify: true,
    dir:  top.lang === 'ar' ? 'rtl' : 'ltr',
    lang: top.lang === 'ar' ? 'ar' : 'en',
  });
  notif.onclick = () => { window.focus(); notif.close(); };
}

/* ── In-app Notification Panel ─────────────────────────────────────────────── */
let unreadCount = 0;

function addInAppNotifications(articles) {
  // Remove empty placeholder if present
  $notifList.querySelector('.notif-empty')?.remove();

  // Insert newest first, cap list at 50 items
  articles.forEach(article => {
    const isAr = article.lang === 'ar';
    const item = document.createElement('div');
    item.className = 'notif-item' + (urgencyScore(article.title) >= 3 ? ' notif-item--urgent' : '');
    item.dir = isAr ? 'rtl' : 'ltr';
    item.innerHTML = `
      <span class="notif-source" style="color:${esc(article.color)}">${esc(article.source)}</span>
      <p class="notif-title">${esc(article.title)}</p>
      <time class="notif-time">${timeAgo(article.pubDate)}</time>`;
    item.addEventListener('click', () => {
      closeNotifPanel();
      showArticle(article);
    });
    $notifList.insertBefore(item, $notifList.firstChild);
  });

  // Keep max 50
  while ($notifList.children.length > 50) $notifList.lastChild.remove();

  // Update badge
  unreadCount += articles.length;
  $notifBadge.textContent = unreadCount > 99 ? '99+' : unreadCount;
  $notifBadge.style.display = '';
  $notifBell.classList.add('has-notif');
}

function closeNotifPanel() {
  $notifPanel.style.display = 'none';
  $notifBell.classList.remove('panel-open');
}

$notifBell.addEventListener('click', e => {
  e.stopPropagation();
  const open = $notifPanel.style.display !== 'none';
  if (open) {
    closeNotifPanel();
  } else {
    $notifPanel.style.display = '';
    $notifBell.classList.add('panel-open');
    // Mark as read
    unreadCount = 0;
    $notifBadge.style.display = 'none';
    $notifBell.classList.remove('has-notif');
  }
});

$notifClear.addEventListener('click', () => {
  $notifList.innerHTML = '<div class="notif-empty">لا توجد إشعارات بعد</div>';
  unreadCount = 0;
  $notifBadge.style.display = 'none';
  $notifBell.classList.remove('has-notif');
});

// Close panel when clicking outside
document.addEventListener('click', e => {
  if (!$notifPanel.contains(e.target) && e.target !== $notifBell) closeNotifPanel();
});

function setStatus(type, text) {
  $liveDot.className = 'live-dot' + (type ? ` ${type}` : '');
  $statusLbl.textContent = text;
}

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/* ── Urgency scoring ───────────────────────────────────────────────────────── */
const URGENCY_RULES = [
  // score 3 — critical
  [/عاجل|عاجلاً|عـاجل/,                                                          3],
  [/مقتل|قتلى|قتيل|شهيد|شهداء|اغتيال|اغتيل|انفجار|تفجير/,                       3],
  [/\bbreaking\b|\burgent\b|\bkilled\b|\bdead\b|\bexplosion\b|\bassassination\b/i, 3],
  // score 2 — serious
  [/هجوم|غارة|قصف|حريق|أزمة|ضحايا|جرحى|مجزرة|اختطاف|احتجاز|حرب|اشتباك/,        2],
  [/\battack\b|\bairstrike\b|\bfire\b|\bcrisis\b|\bcasualt|\bwounded\b|\bwar\b|\bhostage\b|\bblast\b/i, 2],
  // score 1 — notable
  [/توتر|تصعيد|تحذير|إنذار|مظاهرات|احتجاجات|اعتقال|حصار/,                        1],
  [/\btension\b|\bescalation\b|\bwarning\b|\bprotest\b|\bsanction\b|\bblockade\b/i, 1],
];

function urgencyScore(title) {
  let score = 0;
  for (const [re, s] of URGENCY_RULES) if (re.test(title)) score += s;
  return score;
}

/* ── Filter helpers ────────────────────────────────────────────────────────── */
function articleVisible(article) {
  if (state.activeSource !== 'all' && article.source !== state.activeSource) return false;
  if (state.activeLang   !== 'all' && article.lang   !== state.activeLang)   return false;
  if (state.activeUrgent && urgencyScore(article.title) === 0) return false;
  return true;
}

/* ── Card Builder ──────────────────────────────────────────────────────────── */
function buildCard(article, isNew = false) {
  const isAr = article.lang === 'ar';
  const a    = document.createElement('a');

  a.className = 'card' + (isNew ? ' is-new' : '');
  a.href      = article.link || '#';
  a.target    = '_blank';
  a.rel       = 'noopener noreferrer';
  a.setAttribute('data-id',   article.id);
  a.setAttribute('data-lang', article.lang || 'en');
  a.setAttribute('data-src',  article.source);
  if (isAr) a.setAttribute('dir', 'rtl');
  a.style.setProperty('--src-color', article.color);

  // Use server-resolved domain; skip news.google.com (no useful favicon)
  const domain = (article.domain || '').replace(/^news\.google\..+/, '');
  const faviconUrl = domain ? `https://www.google.com/s2/favicons?domain=${domain}&sz=128` : '';
  const placeholderInner = faviconUrl
    ? `<img class="source-logo" src="${esc(faviconUrl)}" alt=""
           onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'source-initial',textContent:'${esc(article.source.charAt(0))}'}))">
       <span class="source-name">${esc(article.source)}</span>`
    : `<span class="source-initial">${esc(article.source.charAt(0))}</span>`;

  let imgHtml;
  if (article.image && !article.aiImage) {
    imgHtml = `<div class="card-img-wrap">
      <img class="card-img" src="${esc(article.image)}" alt="" loading="lazy"
           onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
      <div class="card-img-placeholder" style="display:none">${placeholderInner}</div>
    </div>`;
  } else {
    imgHtml = `<div class="card-img-placeholder">${placeholderInner}</div>`;
  }

  a.innerHTML = `
    ${imgHtml}
    <div class="card-body">
      <div class="card-meta">
        <span class="card-source">${esc(article.source)}</span>
        <span class="card-lang-badge">${isAr ? 'AR' : 'EN'}</span>
        ${isNew ? '<span class="badge-new"></span>' : ''}
      </div>
      <h2 class="card-title">${esc(article.title)}</h2>
      ${article.description ? `<p class="card-desc">${esc(article.description)}</p>` : ''}
      <div class="card-footer">
        <time class="card-time">${timeAgo(article.pubDate)}</time>
        <span class="card-arrow">→</span>
      </div>
    </div>`;

  return a;
}

/* ── Stack-style prepend (new articles appear at front) ────────────────────── */
function prependArticles(newArticles) {
  // Sort new articles newest-first before inserting
  const sorted = [...newArticles].sort(
    (a, b) => new Date(b.pubDate) - new Date(a.pubDate)
  );

  const firstExisting = $grid.querySelector('.card[data-id]');

  sorted.forEach(article => {
    if (!articleVisible(article)) return;
    const el = buildCard(article, true);
    if (firstExisting) {
      $grid.insertBefore(el, firstExisting);
    } else {
      $grid.appendChild(el);
    }
    state.renderedIds.add(article.id);
  });
}

/* ── Initial full render ────────────────────────────────────────────────────── */
function initialRender(articles) {
  // Clear skeletons & empty state
  $grid.innerHTML = '';
  state.renderedIds.clear();

  const sortFn = state.activeUrgent
    ? (a, b) => urgencyScore(b.title) - urgencyScore(a.title) || new Date(b.pubDate) - new Date(a.pubDate)
    : (a, b) => new Date(b.pubDate) - new Date(a.pubDate);
  const visible = articles.filter(articleVisible).sort(sortFn);

  if (visible.length === 0) {
    $grid.innerHTML = `
      <div class="empty-state">
        <h3>لا توجد أخبار</h3>
        <p>جارٍ جلب الأخبار من المصادر العربية…</p>
      </div>`;
    return;
  }

  const frag = document.createDocumentFragment();
  visible.forEach(article => {
    frag.appendChild(buildCard(article, false));
    state.renderedIds.add(article.id);
  });
  $grid.appendChild(frag);
}

/* ── Re-filter without refetch ─────────────────────────────────────────────── */
function applyFilter() {
  // Urgency filter needs sorted re-render; others just show/hide
  if (state.activeUrgent) {
    initialRender([...state.articles.values()]);
    return;
  }

  let anyVisible = false;
  $grid.querySelectorAll('.card[data-id]').forEach(el => {
    const id      = el.getAttribute('data-id');
    const article = state.articles.get(id);
    if (!article) { el.style.display = 'none'; return; }
    const show = articleVisible(article);
    el.style.display = show ? '' : 'none';
    if (show) anyVisible = true;
  });

  $grid.querySelector('.empty-state')?.remove();
  if (!anyVisible) {
    $grid.insertAdjacentHTML('beforeend', `
      <div class="empty-state">
        <h3>لا توجد نتائج</h3>
        <p>حاول تغيير الفلتر</p>
      </div>`);
  }
}

/* ── Source Filter Buttons ─────────────────────────────────────────────────── */
const knownSources = new Set(['all']);

function ensureSourceBtn(src) {
  if (knownSources.has(src.name)) return;
  knownSources.add(src.name);
  const btn = document.createElement('button');
  btn.className      = 'filter-btn';
  btn.dataset.source = src.name;
  btn.style.setProperty('--src-color', src.color);
  btn.innerHTML      = `<span style="color:${src.color}">●</span> ${src.name}`;
  $filterBar.appendChild(btn);
}

$filterBar.addEventListener('click', e => {
  const btn = e.target.closest('.filter-btn');
  if (!btn) return;
  $filterBar.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  state.activeSource = btn.dataset.source;
  applyFilter();
});

/* ── Language Toggle ──────────────────────────────────────────────────────── */
document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.lang-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    state.activeLang = btn.dataset.lang;
    applyFilter();
  });
});

/* ── Urgency Filter Toggle ─────────────────────────────────────────────────── */
const $urgentBtn = document.getElementById('urgentBtn');
$urgentBtn.addEventListener('click', () => {
  state.activeUrgent = !state.activeUrgent;
  $urgentBtn.classList.toggle('active', state.activeUrgent);
  applyFilter();
});

/* ── Fetch ─────────────────────────────────────────────────────────────────── */
async function fetchNews() {
  try {
    const res  = await fetch(`/api/news?since=${state.lastFetch}&page=1&limit=90`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    // Update pagination state
    state.currentPage = 1;
    state.hasMore     = data.hasMore || false;
    updateLoadMoreBtn();

    // Split into new vs known
    const brandNew = [];
    data.articles.forEach(article => {
      const isNew = !state.articles.has(article.id);
      state.articles.set(article.id, article);
      if (isNew) brandNew.push(article);
      // Add source button if needed
      ensureSourceBtn({ name: article.source, color: article.color });
    });

    state.lastFetch = Date.now();
    setStatus('live', 'مباشر');
    $count.textContent = `${data.total} خبر`;

    if (!state.initialized && data.articles.length > 0) {
      // First load — full render (only mark initialized once we have articles)
      state.initialized = true;
      initialRender(data.articles);
      requestNotifPermission();
    } else if (brandNew.length > 0) {
      // Subsequent fetch — ONLY prepend truly new articles (stack behavior)
      prependArticles(brandNew);
      showToast(`+${brandNew.length} ${brandNew.length === 1 ? 'خبر جديد' : 'أخبار جديدة'}`);
      addInAppNotifications(brandNew);
      pushNotification(brandNew);
    }
    // If brandNew.length === 0 → nothing to do, no re-render
  } catch (err) {
    setStatus('error', 'إعادة الاتصال…');
    console.warn('Fetch error:', err.message);
  }
}

/* ── Load More ─────────────────────────────────────────────────────────────── */
function updateLoadMoreBtn() {
  let btn = document.getElementById('loadMoreBtn');
  if (!btn) return;
  if (state.hasMore) {
    btn.style.display = '';
    btn.disabled      = state.loadingMore;
    btn.textContent   = state.loadingMore ? 'جارٍ التحميل…' : 'تحميل المزيد (90 خبراً)';
  } else {
    btn.style.display = 'none';
  }
}

async function loadMoreNews() {
  if (state.loadingMore || !state.hasMore) return;
  state.loadingMore = true;
  updateLoadMoreBtn();
  try {
    const nextPage = state.currentPage + 1;
    const res  = await fetch(`/api/news?page=${nextPage}&limit=90`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    state.currentPage = nextPage;
    state.hasMore     = data.hasMore || false;

    const newArticles = [];
    data.articles.forEach(article => {
      if (!state.articles.has(article.id)) {
        state.articles.set(article.id, article);
        newArticles.push(article);
        ensureSourceBtn({ name: article.source, color: article.color });
      }
    });

    // Append to grid
    if (newArticles.length > 0) {
      const frag = document.createDocumentFragment();
      const sortFn = (a, b) => new Date(b.pubDate) - new Date(a.pubDate);
      newArticles.sort(sortFn).forEach(article => {
        if (!articleVisible(article)) return;
        frag.appendChild(buildCard(article, false));
        state.renderedIds.add(article.id);
      });
      // Insert before the load-more button
      const btn = document.getElementById('loadMoreBtn');
      $grid.insertBefore(frag, btn);
    }
  } catch (err) {
    console.warn('Load more error:', err.message);
  }
  state.loadingMore = false;
  updateLoadMoreBtn();
}

/* ── Countdown ─────────────────────────────────────────────────────────────── */
function startCountdown() {
  state.nextIn = INTERVAL_SEC;
  clearInterval(state.countdownId);
  state.countdownId = setInterval(() => {
    state.nextIn = Math.max(0, state.nextIn - 1);
    if (state.nextIn > 60) {
      $nextUpd.textContent = `تحديث بعد ${Math.ceil(state.nextIn / 60)}د`;
    } else if (state.nextIn > 0) {
      $nextUpd.textContent = `تحديث بعد ${state.nextIn}ث`;
    } else {
      $nextUpd.textContent = 'يتم التحديث…';
    }
  }, 1000);
}

/* ── Refresh time labels ──────────────────────────────────────────────────── */
setInterval(() => {
  $grid.querySelectorAll('.card[data-id]').forEach(el => {
    const art = state.articles.get(el.getAttribute('data-id'));
    if (art) {
      const t = el.querySelector('.card-time');
      if (t) t.textContent = timeAgo(art.pubDate);
    }
  });
}, 30000);

/* ── Modal ─────────────────────────────────────────────────────────────────── */
const prefetchCache = new Map();   // url → Promise<data>
let   prefetchTimer  = null;
let   modalOpen      = false;

function formatDate(iso) {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleDateString('ar-EG', {
      year: 'numeric', month: 'long', day: 'numeric'
    });
  } catch (_) { return ''; }
}

function openModal() {
  $overlay.classList.add('open');
  document.body.style.overflow = 'hidden';
  modalOpen = true;
}

function closeModal() {
  $overlay.classList.remove('open');
  document.body.style.overflow = '';
  modalOpen = false;
}

function showModalLoading() {
  $modalLoading.style.display = '';
  $modalContent.style.display = 'none';
  $modalError.style.display   = 'none';
}

function showModalContent(data, article) {
  const isAr = article.lang === 'ar' || /[\u0600-\u06FF]/.test(data.title || '');

  // Hero image — use scraped og:image only (skip AI-generated images)
  const heroImg = data.image || (!article.aiImage ? article.image : null);
  const modalDomain = article.domain || '';
  const modalFavicon = modalDomain ? `https://www.google.com/s2/favicons?domain=${modalDomain}&sz=128` : '';
  if (heroImg) {
    $modalHero.innerHTML = `<img src="${esc(heroImg)}" alt="" loading="lazy"
      onerror="this.parentElement.style.display='none'">`;
    $modalHero.style.display = '';
  } else if (modalFavicon) {
    $modalHero.innerHTML = `<div class="modal-logo-placeholder">
      <img src="${esc(modalFavicon)}" alt="" class="source-logo source-logo--lg"
           onerror="this.style.display='none'">
      <span>${esc(article.source)}</span>
    </div>`;
    $modalHero.style.display = '';
  } else {
    $modalHero.innerHTML = '';
    $modalHero.style.display = 'none';
  }

  // Meta row
  const pubDate = formatDate(data.published) || timeAgo(article.pubDate);
  const author  = data.author ? `<span class="modal-author">· ${esc(data.author)}</span>` : '';
  const site    = data.siteName ? `<span class="modal-site-name">${esc(data.siteName)}</span>` : '';
  $modalMeta.innerHTML = `
    <span class="modal-source-badge" style="background:${esc(article.color)}">${esc(article.source)}</span>
    ${site}
    ${author}
    <time class="modal-pub-time">${esc(pubDate)}</time>`;

  // Title
  const title = data.title || article.title;
  $modalTitle.textContent = title;
  $modalTitle.dir = isAr ? 'rtl' : '';

  // Description
  const desc = data.description || article.description;
  if (desc) {
    $modalDesc.textContent = desc;
    $modalDesc.dir = isAr ? 'rtl' : '';
    $modalDesc.style.display = '';
  } else {
    $modalDesc.style.display = 'none';
  }

  // Article body
  if (data.body && data.body.length > 80) {
    $modalBody.textContent = data.body;
    $modalBody.dir = isAr ? 'rtl' : '';
    $modalBody.style.display = '';
  } else {
    $modalBody.style.display = 'none';
  }

  // Read button
  $modalReadBtn.href = article.link;
  $modalReadBtn.querySelector('#modalReadBtnText').textContent =
    isAr ? 'قراءة المقال كاملاً' : 'Read full article';

  $modalLoading.style.display = 'none';
  $modalContent.style.display = '';
  $modalError.style.display   = 'none';
}

function showModalError(article) {
  $modalLoading.style.display = 'none';
  $modalContent.style.display = 'none';
  $modalError.style.display   = '';
  $modalErrMsg.textContent    = article.lang === 'ar'
    ? 'تعذّر تحميل تفاصيل المقال. اضغط لفتحه مباشرة.'
    : 'Could not load article details. Open it directly.';
  $modalErrBtn.href = article.link;
}

async function fetchArticleDetail(url) {
  if (!prefetchCache.has(url)) {
    prefetchCache.set(url, fetch(`/api/article?url=${encodeURIComponent(url)}`).then(r => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    }));
  }
  return prefetchCache.get(url);
}

async function showArticle(article) {
  openModal();
  showModalLoading();

  // Scroll modal body to top
  const mb = document.getElementById('modalBody');
  if (mb) mb.scrollTop = 0;

  try {
    const data = await fetchArticleDetail(article.link);
    showModalContent(data, article);
  } catch (_) {
    showModalError(article);
  }
}

// Close on overlay click / Escape
$overlay.addEventListener('click', e => { if (e.target === $overlay) closeModal(); });
$modalClose.addEventListener('click', closeModal);
document.addEventListener('keydown', e => { if (e.key === 'Escape' && modalOpen) closeModal(); });

// Grid: intercept card clicks + prefetch on hover
$grid.addEventListener('click', e => {
  const card = e.target.closest('.card[data-id]');
  if (!card) return;
  e.preventDefault();
  const id      = card.getAttribute('data-id');
  const article = state.articles.get(id);
  if (article?.link) showArticle(article);
});

$grid.addEventListener('mouseover', e => {
  const card = e.target.closest('.card[data-id]');
  if (!card) return;
  clearTimeout(prefetchTimer);
  prefetchTimer = setTimeout(() => {
    const id      = card.getAttribute('data-id');
    const article = state.articles.get(id);
    if (article?.link && !prefetchCache.has(article.link)) {
      fetchArticleDetail(article.link).catch(() => {});
    }
  }, 250);  // 250 ms debounce — only prefetch when actually hovering
});

/* ── Init ──────────────────────────────────────────────────────────────────── */
async function init() {
  // Create "Load More" button and append below grid
  const loadMoreBtn = document.createElement('button');
  loadMoreBtn.id          = 'loadMoreBtn';
  loadMoreBtn.textContent = 'تحميل المزيد (90 خبراً)';
  loadMoreBtn.style.cssText = [
    'display:none', 'margin:32px auto', 'padding:12px 32px',
    'background:#1a1a2e', 'color:#fff', 'border:1px solid #333',
    'border-radius:30px', 'font-size:15px', 'cursor:pointer',
    'font-family:inherit', 'width:fit-content',
  ].join(';');
  loadMoreBtn.addEventListener('click', loadMoreNews);
  $grid.parentNode.insertBefore(loadMoreBtn, $grid.nextSibling);

  setStatus('', 'جارٍ الاتصال…');
  await fetchNews();

  // Keep retrying every 4s until articles arrive (server cold-start can take 30-60s)
  if (state.articles.size === 0) {
    const warmup = setInterval(async () => {
      if (state.articles.size > 0) { clearInterval(warmup); return; }
      await fetchNews();
    }, 4000);
    // Stop warmup once the regular interval fires (it will fetch too)
    setTimeout(() => clearInterval(warmup), INTERVAL_SEC * 1000);
  }

  startCountdown();
  setInterval(async () => {
    startCountdown();
    await fetchNews();
  }, INTERVAL_SEC * 1000);
}

init();
