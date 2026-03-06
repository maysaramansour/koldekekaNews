const express = require('express');
const Parser  = require('rss-parser');
const https   = require('https');
const http    = require('http');
const path    = require('path');

const app = express();

// ── Multiple User-Agents to rotate through for blocked sites ─────────────────
const USER_AGENTS = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_3_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3.1 Safari/605.1.15',
  'Feedparser/3.0 (https://github.com/rbren/rss-parser)',
];

let uaIndex = 0;
function nextUA() {
  return USER_AGENTS[uaIndex++ % USER_AGENTS.length];
}

// ── RSS Parser factory (fresh instance per request to vary headers) ───────────
function makeParser(ua, extraHeaders = {}) {
  return new Parser({
    timeout: 15000,
    headers: {
      'User-Agent':       ua,
      'Accept':           'application/rss+xml, application/xml, text/xml, */*',
      'Accept-Language':  'en-US,en;q=0.9',
      'Cache-Control':    'no-cache',
      'Pragma':           'no-cache',
      ...extraHeaders
    },
    customFields: {
      item: [
        ['media:content',   'mediaContent'],
        ['media:thumbnail', 'mediaThumbnail'],
      ]
    }
  });
}

// ── Low-level raw fetch (bypasses rss-parser's http agent) ───────────────────
function rawFetch(url, ua) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https') ? https : http;
    const req = lib.get(url, {
      headers: {
        'User-Agent':       ua,
        'Accept':           'application/rss+xml, application/xml, text/xml, */*',
        'Accept-Language':  'en-US,en;q=0.9',
        'Cache-Control':    'no-cache',
        'Connection':       'keep-alive',
      }
    }, res => {
      // Follow one redirect
      if ((res.statusCode === 301 || res.statusCode === 302) && res.headers.location) {
        return rawFetch(res.headers.location, ua).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`Status ${res.statusCode}`));
      }
      let data = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => resolve(data));
    });
    req.setTimeout(14000, () => { req.destroy(); reject(new Error('Timeout')); });
    req.on('error', reject);
  });
}

// ── Feed definitions (Arabic only) ───────────────────────────────────────────
const FEEDS = [
  // الجزيرة & العربية via Google News (reliable proxy, no blocking)
  { name: 'الجزيرة', url: 'https://news.google.com/rss/search?q=site:aljazeera.net&hl=ar&gl=SA&ceid=SA:ar', color: '#a93226', gnews: true, forceName: 'الجزيرة', lang: 'ar', domain: 'aljazeera.net' },
  { name: 'العربية', url: 'https://news.google.com/rss/search?q=site:alarabiya.net&hl=ar&gl=SA&ceid=SA:ar', color: '#884ea0', gnews: true, forceName: 'العربية', lang: 'ar', domain: 'alarabiya.net' },
  // Others via own direct RSS feeds
  { name: 'BBC عربي',         url: 'https://feeds.bbci.co.uk/arabic/rss.xml',  color: '#c0392b', lang: 'ar' },
  { name: 'RT عربي',          url: 'https://arabic.rt.com/rss/',               color: '#e74c3c', lang: 'ar' },
  { name: 'DW عربية',         url: 'https://rss.dw.com/xml/rss-ar-all',        color: '#2471a3', lang: 'ar' },
  { name: 'فرانس 24',         url: 'https://www.france24.com/ar/rss',          color: '#1a5276', lang: 'ar' },
  { name: 'سكاي نيوز عربية', url: 'https://www.skynewsarabia.com/rss',        color: '#117a65', lang: 'ar' },
  { name: 'القدس',            url: 'https://www.alquds.com/feed/',              color: '#2c3e50', lang: 'ar' },
];

// No BLOCKED_FEEDS needed — all feeds now use rss-parser
const BLOCKED_FEEDS = [];

// ── AI image generation (Pollinations.ai — free, no API key) ─────────────────
// Generates a unique photo-realistic news image from a text prompt.
// URL is returned as-is; the browser fetches it on demand (lazy).
function aiImageUrl(title, source) {
  // Use the first ~60 chars of the title as the prompt, in English context
  const prompt = encodeURIComponent(
    `news photo: ${title.replace(/[\u0600-\u06FF]/g, '').trim() || source} middle east journalism`
  );
  // Seed from title so the same article always gets the same image
  const seed = [...title].reduce((a, c) => (a * 31 + c.charCodeAt(0)) | 0, 0);
  return `https://image.pollinations.ai/prompt/${prompt}?width=800&height=450&seed=${Math.abs(seed)}&nologo=true`;
}

// ── In-memory store ───────────────────────────────────────────────────────────
let articlesMap = new Map();
let lastUpdated = null;
let fetchCount  = 0;

const sourceStats = {};
[...FEEDS, ...BLOCKED_FEEDS].forEach(f => {
  sourceStats[f.forceName || f.name] = { success: false, count: 0, error: null };
});

// ── Helpers ───────────────────────────────────────────────────────────────────
function extractImage(item) {
  try {
    if (item.mediaContent) {
      const mc = Array.isArray(item.mediaContent) ? item.mediaContent[0] : item.mediaContent;
      if (mc?.$?.url) return mc.$.url;
    }
    if (item.mediaThumbnail) {
      const mt = Array.isArray(item.mediaThumbnail) ? item.mediaThumbnail[0] : item.mediaThumbnail;
      if (mt?.$?.url) return mt.$.url;
    }
    if (item.enclosure?.url && /\.(jpe?g|png|webp|gif)/i.test(item.enclosure.url)) return item.enclosure.url;
    const html = item.content || item['content:encoded'] || '';
    const m = html.match(/<img[^>]+src=["']([^"']+)["']/i);
    if (m) return m[1];
  } catch (_) {}
  return null;
}

function cleanText(t) {
  if (!t) return '';
  return t
    .replace(/<[^>]*>/g, '')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ')
    // Strip RT-style social UI noise embedded in descriptions
    .replace(/\bSTORIES\s+\d+\b/gi, '')
    .replace(/\bSave\s+post\b/gi, '')
    .replace(/\bShare\b/gi, '')
    .replace(/\bFacebook\b/gi, '')
    .replace(/\bVK\.com\b/gi, '')
    .replace(/\bTelegram\b/gi, '')
    .replace(/\bQuestion_More\s+RT\b/gi, '')
    .replace(/#اسأل_أكثر\b/g, '')
    .replace(/اضغط للمزيد/g, '')
    .replace(/\(فيديوهات\)/g, '')
    // Google News channel-level boilerplate (appears when article has no description)
    .replace(/Comprehensive up-to-date news coverage,?\s*aggregated from sources all over the world by Google News\.?/gi, '')
    .replace(/aggregated from sources all over the world by Google News\.?/gi, '')
    .replace(/This is a Google News feed[^.]*\./gi, '')
    // English boilerplate / subscription walls
    .replace(/\bSubscribe\s+(to\s+)?(read|continue|access|unlock)[^.!?]*/gi, '')
    .replace(/\bSign\s+up\s+(to\s+)?read[^.!?]*/gi, '')
    .replace(/\bContinue\s+reading[^.!?]*/gi, '')
    .replace(/\bRead\s+(the\s+)?(full\s+)?(story|article|more)[^.!?]*/gi, '')
    .replace(/\bAll\s+rights\s+reserved[^.!?]*/gi, '')
    .replace(/©\s*\d{4}[^.\n]*/g, '')
    .replace(/\[(?:VIDEO|PHOTOS?|GALLERY|\.\.\.)\]/gi, '')
    .replace(/\[…\]/g, '')
    // Arabic boilerplate
    .replace(/اشترك\s*(الآن|للاطلاع|للقراءة)[^.!؟]*/g, '')
    .replace(/للاشتراك\b[^.!؟]*/g, '')
    .replace(/اقرأ\s+المزيد/g, '')
    .replace(/لمزيد\s+من\s+التفاصيل[^.!؟]*/g, '')
    .replace(/انقر\s+هنا[^.!؟]*/g, '')
    .replace(/\s{2,}/g, ' ').trim();
}

function truncateAtSentence(text, maxLen) {
  if (!text || text.length <= maxLen) return text;
  const cut = text.substring(0, maxLen);
  const last = Math.max(cut.lastIndexOf('.'), cut.lastIndexOf('!'), cut.lastIndexOf('?'), cut.lastIndexOf('؟'), cut.lastIndexOf('!'), cut.lastIndexOf('.'));
  return last > maxLen * 0.5 ? text.substring(0, last + 1) : cut.trimEnd() + '…';
}

function parseGNewsTitle(raw) {
  const i = raw.lastIndexOf(' - ');
  return i > 0 ? { title: raw.slice(0, i).trim() } : { title: raw.trim() };
}

function makeId(item) { return item.guid || item.link || item.title || ''; }

function isArabicText(str) {
  const ar = (str || '').match(/[\u0600-\u06FF]/g) || [];
  return ar.length > (str || '').length * 0.3;
}

function itemToArticle(item, feed) {
  let title = cleanText(item.title);
  if (feed.gnews) title = parseGNewsTitle(title).title;
  const rawDesc = cleanText(item.contentSnippet || item.description || '');
  // Drop description if it's just leftover boilerplate (< 20 chars after cleaning)
  const desc = rawDesc.length >= 20 ? truncateAtSentence(rawDesc, 220) : '';
  const lang = feed.lang || (isArabicText(title) ? 'ar' : 'en');
  const source = feed.forceName || feed.name;
  const image  = extractImage(item) || aiImageUrl(title, source);
  // For gnews feeds use the declared domain; for direct feeds derive from link
  let domain = feed.domain || '';
  if (!domain && item.link) {
    try { domain = new URL(item.link).hostname.replace(/^www\./, ''); } catch(_) {}
  }
  return {
    id:        makeId(item),
    title,
    link:      item.link || '',
    description: desc,
    pubDate:   item.isoDate ? new Date(item.isoDate) : (item.pubDate ? new Date(item.pubDate) : new Date()),
    source,
    color:     feed.color,
    lang,
    image,
    aiImage:   !extractImage(item),
    domain,
    fetchedAt: Date.now()
  };
}

// ── Fetch: standard rss-parser ────────────────────────────────────────────────
async function fetchFeed(feed) {
  const ua = nextUA();
  try {
    const p       = makeParser(ua, feed.gnews ? {} : { Referer: new URL(feed.url).origin + '/' });
    const result  = await p.parseURL(feed.url);
    const articles = result.items
      .filter(i => i.title && (i.link || i.guid))
      .map(i => itemToArticle(i, feed));
    sourceStats[feed.forceName || feed.name] = { success: true, count: articles.length, error: null };
    return articles;
  } catch (err) {
    sourceStats[feed.forceName || feed.name] = { success: false, count: 0, error: err.message };
    return [];
  }
}

// ── Fetch: raw HTTP + manual XML parse (for blocked sites) ───────────────────
async function fetchBlocked(feed) {
  const ua = nextUA();
  try {
    const xml = await rawFetch(feed.url, ua);

    // Quick XML → items parse (no external dependency)
    const items = [];
    const itemRx  = /<item[^>]*>([\s\S]*?)<\/item>/gi;
    const tagRx   = (tag) => new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const cdataRx = /<!\[CDATA\[([\s\S]*?)\]\]>/;

    let m;
    while ((m = itemRx.exec(xml)) !== null) {
      const block = m[1];
      const get   = (tag) => {
        const r = tagRx(tag).exec(block);
        if (!r) return '';
        const inner = r[1].trim();
        const cd = cdataRx.exec(inner);
        return cd ? cd[1].trim() : inner;
      };

      const linkM  = /<link>([^<]+)<\/link>/.exec(block) || /<link href=["']([^"']+)["']/.exec(block);
      const guidM  = /<guid[^>]*>([^<]+)<\/guid>/.exec(block);
      const encM   = /url=["']([^"']+\.(?:jpe?g|png|webp|gif))[^"']*["']/.exec(block);

      items.push({
        title:          get('title'),
        link:           linkM ? linkM[1].trim() : '',
        description:    get('description') || get('summary'),
        pubDate:        get('pubDate') || get('published') || get('dc:date'),
        guid:           guidM ? guidM[1].trim() : '',
        enclosure:      encM  ? { url: encM[1] } : null,
        content:        get('content') || get('content:encoded'),
        contentSnippet: ''
      });
    }

    const articles = items
      .filter(i => i.title && (i.link || i.guid))
      .map(i => itemToArticle(i, feed));

    if (articles.length > 0) {
      sourceStats[feed.forceName || feed.name] = { success: true, count: articles.length, error: null };
      console.log(`  [${feed.forceName || feed.name}] raw fetch OK — ${articles.length} items`);
    }
    return articles;
  } catch (err) {
    // Silently skip — Google News feed covers this source anyway
    return [];
  }
}

// ── Main update loop ──────────────────────────────────────────────────────────
async function updateFeeds() {
  fetchCount++;
  process.stdout.write(`[#${fetchCount}] Fetching feeds… `);

  const [standardResults, blockedResults] = await Promise.all([
    Promise.allSettled(FEEDS.map(fetchFeed)),
    Promise.allSettled(BLOCKED_FEEDS.map(fetchBlocked))
  ]);

  let added = 0;
  [...standardResults, ...blockedResults].forEach(result => {
    if (result.status === 'fulfilled') {
      result.value.forEach(article => {
        if (article.id && !articlesMap.has(article.id)) {
          articlesMap.set(article.id, article);
          added++;
        }
      });
    }
  });

  // Cap at 1000 most recent
  if (articlesMap.size > 1000) {
    const sorted = [...articlesMap.entries()]
      .sort((a, b) => new Date(b[1].pubDate) - new Date(a[1].pubDate))
      .slice(0, 1000);
    articlesMap = new Map(sorted);
  }

  lastUpdated = Date.now();
  console.log(`+${added} new | total ${articlesMap.size}`);
}

// Start immediately, then every 2 minutes
updateFeeds();
setInterval(updateFeeds, 60000);

// ── Article scraper ───────────────────────────────────────────────────────────
// In-memory cache: url → { data, ts }
const articleCache = new Map();
const CACHE_TTL    = 10 * 60 * 1000; // 10 min

function decodeMeta(s) {
  return (s || '')
    .replace(/&amp;/g,  '&').replace(/&lt;/g,   '<')
    .replace(/&gt;/g,   '>').replace(/&quot;/g, '"')
    .replace(/&#39;/g,  "'").replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n))
    .trim();
}

function metaVal(html, ...props) {
  for (const prop of props) {
    // property= or name= attribute, content= may come before or after
    const rx = [
      new RegExp(`<meta[^>]+(?:property|name)=["']${prop}["'][^>]+content=["']([^"'<>]{1,600})["']`, 'i'),
      new RegExp(`<meta[^>]+content=["']([^"'<>]{1,600})["'][^>]+(?:property|name)=["']${prop}["']`, 'i'),
    ];
    for (const r of rx) {
      const m = html.match(r);
      if (m?.[1]) return decodeMeta(m[1]);
    }
  }
  return null;
}

function extractArticleBody(html) {
  // Strip <head>, scripts, styles, nav, footer, aside, ads
  let body = html
    .replace(/<head[\s\S]*?<\/head>/gi, '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<(nav|footer|aside|header|figure|figcaption|form|iframe|noscript|svg)[^>]*>[\s\S]*?<\/\1>/gi, '');

  // Try to narrow to the article element
  const selectors = [
    /<article[^>]*>([\s\S]*?)<\/article>/i,
    /<div[^>]+class=["'][^"']*(?:article-body|story-body|post-content|entry-content|article-content|articleBody|article__body|content-body|article-text|news-body)[^"']*["'][^>]*>([\s\S]*?)<\/div>/i,
    /<main[^>]*>([\s\S]*?)<\/main>/i,
  ];

  let candidate = '';
  for (const rx of selectors) {
    const m = body.match(rx);
    if (m) { candidate = m[1]; break; }
  }
  if (!candidate) candidate = body;

  // Strip remaining tags, collapse whitespace
  const text = candidate
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s{2,}/g, ' ')
    .trim();

  // Return first ~800 chars of meaningful text
  return text.length > 100 ? text.substring(0, 900) : null;
}

async function scrapeArticle(url) {
  const cached = articleCache.get(url);
  if (cached && Date.now() - cached.ts < CACHE_TTL) return cached.data;

  const html = await rawFetch(url, nextUA());

  const data = {
    title:       metaVal(html, 'og:title', 'twitter:title'),
    description: metaVal(html, 'og:description', 'twitter:description', 'description'),
    image:       metaVal(html, 'og:image', 'twitter:image:src', 'twitter:image'),
    author:      metaVal(html, 'article:author', 'author', 'twitter:creator'),
    published:   metaVal(html, 'article:published_time', 'article:modified_time', 'pubdate'),
    siteName:    metaVal(html, 'og:site_name'),
    body:        extractArticleBody(html),
    url,
    scrapedAt:   Date.now(),
  };

  articleCache.set(url, { data, ts: Date.now() });
  // Limit cache size
  if (articleCache.size > 200) {
    const oldest = [...articleCache.entries()].sort((a, b) => a[1].ts - b[1].ts)[0];
    articleCache.delete(oldest[0]);
  }
  return data;
}

// ── API ───────────────────────────────────────────────────────────────────────
app.use(express.static(path.join(__dirname, 'public')));

app.get('/api/article', async (req, res) => {
  const url = req.query.url;
  if (!url || !/^https?:\/\//.test(url)) {
    return res.status(400).json({ error: 'Invalid URL' });
  }
  try {
    const data = await scrapeArticle(url);
    res.json(data);
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

app.get('/api/news', (req, res) => {
  const since  = parseInt(req.query.since) || 0;
  const source = req.query.source || 'all';
  const page   = Math.max(1, parseInt(req.query.page)  || 1);
  const limit  = Math.min(200, Math.max(1, parseInt(req.query.limit) || 90));

  let articles = [...articlesMap.values()];
  if (source !== 'all') articles = articles.filter(a => a.source === source);

  articles = articles
    .sort((a, b) => new Date(b.pubDate) - new Date(a.pubDate))
    .map(a => ({ ...a, isNew: since > 0 && a.fetchedAt > since }));

  const total      = articles.length;
  const totalPages = Math.ceil(total / limit) || 1;
  const start      = (page - 1) * limit;
  const paged      = articles.slice(start, start + limit);

  res.json({
    articles:   paged,
    total,
    page,
    totalPages,
    hasMore:    page < totalPages,
    lastUpdated,
    fetchCount
  });
});

app.get('/api/sources', (req, res) => {
  const sourceMap = new Map();
  articlesMap.forEach(a => {
    if (!sourceMap.has(a.source)) sourceMap.set(a.source, { name: a.source, color: a.color });
  });
  res.json([...sourceMap.values()]);
});

app.get('/api/status', (req, res) => {
  res.json({ total: articlesMap.size, lastUpdated, fetchCount, sources: sourceStats });
});

// ═══════════════════════════════════════════════════════════════════════════════
// ── VIDEOS: YouTube RSS scraping ─────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

const VIDEO_CHANNELS = [
  // ── Verified channel IDs ───────────────────────────────────────────────────
  { name: 'الجزيرة',           channelId: 'UCfiwzLy-8yKzIbsmZTzxDgw', color: '#a93226', lang: 'ar' },
  { name: 'Al Jazeera Eng',    channelId: 'UCB87_o2zsNZTrJ9MO6DdM-A', color: '#c0392b', lang: 'en' },
  { name: 'العربية',           channelId: 'UCahpxixMCwoANAftn6IxkTg', color: '#884ea0', lang: 'ar' },
  { name: 'سكاي نيوز عربية',  channelId: 'UCIJXOvggjKtCagMfxvcCzAA', color: '#1a5276', lang: 'ar' },
  { name: 'DW عربية',          channelId: 'UC30ditU5JI16o5NbFsHde_Q', color: '#2471a3', lang: 'ar' },
  { name: 'قناة الحرة',        channelId: 'UCyscVWiJELkATSuU-RF2NLg', color: '#27ae60', lang: 'ar' },
  { name: 'Middle East Eye',   channelId: 'UCR0fZh5SBxxMNYdg0VzRFkg', color: '#16a085', lang: 'en' },
  { name: 'TRT عربي',          channelId: 'UCP9b8o5C9sVr2sZUBAqRnAg', color: '#d35400', lang: 'ar' },
  { name: 'فرانس 24',          channelId: 'UCdTyuXgmJkG_O8_75eqej-w', color: '#1a5276', lang: 'ar' },
];

let videosMap  = new Map();
const videoStats = {};
VIDEO_CHANNELS.forEach(c => { videoStats[c.name] = { success: false, count: 0, error: null }; });

// ── Parse a YouTube Atom RSS feed (no external lib needed) ─────────────────
async function fetchVideoChannel(ch) {
  const url = `https://www.youtube.com/feeds/videos.xml?channel_id=${ch.channelId}`;
  try {
    const xml  = await rawFetch(url, nextUA());
    const videos = [];
    const entryRx = /<entry>([\s\S]*?)<\/entry>/gi;
    let m;

    while ((m = entryRx.exec(xml)) !== null) {
      const blk = m[1];

      const videoIdM    = /<yt:videoId>([^<]+)<\/yt:videoId>/i.exec(blk);
      const titleM      = /<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/i.exec(blk);
      const publishedM  = /<published>([^<]+)<\/published>/i.exec(blk);
      const thumbnailM  = /<media:thumbnail[^>]+url="([^"]+)"/i.exec(blk);
      const descM       = /<media:description>([\s\S]*?)<\/media:description>/i.exec(blk);

      if (!videoIdM || !titleM) continue;

      const videoId   = videoIdM[1].trim();
      const title     = cleanText(titleM[1]);
      const published = publishedM ? publishedM[1].trim() : new Date().toISOString();
      // Prefer maxresdefault; fall back to hqdefault
      const thumbnail = thumbnailM
        ? thumbnailM[1]
        : `https://img.youtube.com/vi/${videoId}/hqdefault.jpg`;
      const description = descM ? cleanText(descM[1]).substring(0, 220) : '';

      videos.push({
        id:          `yt:${videoId}`,
        videoId,
        title,
        description,
        channel:     ch.name,
        channelId:   ch.channelId,
        color:       ch.color,
        lang:        ch.lang,
        thumbnail,
        published:   new Date(published),
        fetchedAt:   Date.now(),
      });
    }

    videoStats[ch.name] = { success: true, count: videos.length, error: null };
    if (videos.length) console.log(`  [YT:${ch.name}] ${videos.length} videos`);
    return videos;
  } catch (err) {
    videoStats[ch.name] = { success: false, count: 0, error: err.message };
    return [];
  }
}

// ── Push videos to Cloud Function (Firestore persistence) ─────────────────
const CLOUD_SYNC_URL = 'https://us-central1-kol-dekeka.cloudfunctions.net/api/api/sync-videos';
const VIDEO_SYNC_SECRET = 'kd_video_sync_2026';

function pushVideosToCloud(videos) {
  try {
    const body = JSON.stringify({ videos });
    const url = new URL(CLOUD_SYNC_URL);
    const req = https.request({
      hostname: url.hostname,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${VIDEO_SYNC_SECRET}`,
        'Content-Length': Buffer.byteLength(body),
      },
    }, res => {
      let d = '';
      res.on('data', c => { d += c; });
      res.on('end', () => console.log(`[Videos] Cloud sync: ${d.trim()}`));
    });
    req.setTimeout(20000, () => req.destroy());
    req.on('error', () => {}); // fire-and-forget, ignore failures
    req.write(body);
    req.end();
  } catch (_) {}
}

// ── Refresh all video channels ─────────────────────────────────────────────
async function updateVideos() {
  process.stdout.write('[Videos] Fetching YouTube channels… ');
  const results = await Promise.allSettled(VIDEO_CHANNELS.map(fetchVideoChannel));

  let added = 0;
  results.forEach(r => {
    if (r.status === 'fulfilled') {
      r.value.forEach(v => {
        if (v.id && !videosMap.has(v.id)) { videosMap.set(v.id, v); added++; }
      });
    }
  });

  // Cap at 300 most-recent videos
  if (videosMap.size > 300) {
    const sorted = [...videosMap.entries()]
      .sort((a, b) => new Date(b[1].published) - new Date(a[1].published))
      .slice(0, 300);
    videosMap = new Map(sorted);
  }
  console.log(`+${added} new | total ${videosMap.size}`);
  // Push all videos to Cloud Function so Firestore stays updated
  if (videosMap.size > 0) pushVideosToCloud([...videosMap.values()]);
}

// Start immediately, refresh every 10 minutes
updateVideos();
setInterval(updateVideos, 10 * 60 * 1000);

// ── API: /api/videos ───────────────────────────────────────────────────────
app.get('/api/videos', (req, res) => {
  const ch    = req.query.channel || 'all';
  const page  = Math.max(1, parseInt(req.query.page)  || 1);
  const limit = Math.min(50, Math.max(1, parseInt(req.query.limit) || 10));
  let videos = [...videosMap.values()];
  if (ch !== 'all') videos = videos.filter(v => v.channel === ch);
  videos = videos.sort((a, b) => new Date(b.published) - new Date(a.published));
  const total      = videos.length;
  const totalPages = Math.ceil(total / limit) || 1;
  const start      = (page - 1) * limit;
  const paged      = videos.slice(start, start + limit);
  res.json({ videos: paged, total, page, totalPages, hasMore: page < totalPages, stats: videoStats });
});

// ── API: /api/video-channels ───────────────────────────────────────────────
app.get('/api/video-channels', (req, res) => {
  const map = new Map();
  videosMap.forEach(v => {
    if (!map.has(v.channel)) map.set(v.channel, { name: v.channel, color: v.color, channelId: v.channelId });
  });
  res.json([...map.values()]);
});

// ── Start ─────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`\n  أخبار — Arab News Live`);
  console.log(`  http://localhost:${PORT}\n`);
});
