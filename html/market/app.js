/* LS Card Exchange - one app for the sd-phone app (phone.html) and the as-browser website (site.html).
   The shell page sets window.ASC = { mode: 'phone'|'site', call(name, args) -> Promise(data) } before this runs. */
(function () {
    'use strict';
    var ASC = window.ASC;
    var SITE = ASC.mode === 'site';
    var root = document.getElementById('app');

    // ------------------------------------------------------------------ helpers
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function money(n) {
        n = Math.floor(Number(n) || 0);
        return '£' + n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }
    function pct(n) {
        n = Number(n) || 0;
        if (n === 0) return '<span class="muted">0%</span>';
        return '<span class="' + (n > 0 ? 'up' : 'down') + '">' + (n > 0 ? '▲ ' : '▼ ') + Math.abs(n).toFixed(1) + '%</span>';
    }
    var skew = 0;   // server time - our time (seconds)
    function now() { return Date.now() / 1000 + skew; }
    function setNow(t) { if (t) skew = t - Date.now() / 1000; }
    function left(ends) {
        var s = Math.max(0, Math.floor(ends - now()));
        if (s <= 0) return 'Ended';
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
        if (d > 0) return d + 'd ' + h + 'h';
        if (h > 0) return h + 'h ' + m + 'm';
        if (m > 0) return m + 'm ' + (sec < 10 ? '0' : '') + sec + 's';
        return sec + 's';
    }
    function timer(ends) {
        var soon = ends - now() < 300;
        return '<span class="timer num' + (soon ? ' soon' : '') + '" data-ends="' + ends + '">' + left(ends) + '</span>';
    }
    function ago(t) {
        var s = Math.max(0, Math.floor(now() - t));
        if (s < 60) return 'just now';
        if (s < 3600) return Math.floor(s / 60) + 'm ago';
        if (s < 86400) return Math.floor(s / 3600) + 'h ago';
        return Math.floor(s / 86400) + 'd ago';
    }
    function dateStr(t) {
        var d = new Date(t * 1000);
        return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    }
    var I = {
        search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
        chart: '<path d="M3 3v18h18"/><path d="M7 15l4-4 3 3 5-6"/>',
        gavel: '<path d="M14 13l-7.5 7.5a2.1 2.1 0 0 1-3-3L11 10"/><path d="M16 16l6-6M8 8l6-6M9 7l8 8M21 11l-8-8"/>',
        tag: '<path d="M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8z"/><circle cx="7" cy="7" r="1.5"/>',
        grid: '<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="9" rx="1.5"/><rect x="3" y="15" width="7" height="6" rx="1.5"/><rect x="14" y="15" width="7" height="6" rx="1.5"/>',
        shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="M9 12l2 2 4-4"/>',
        back: '<path d="M15 18l-6-6 6-6"/>',
        check: '<path d="M20 6L9 17l-5-5"/>',
        x: '<path d="M18 6L6 18M6 6l12 12"/>',
        q: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>',
        bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
        eye: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>',
        box: '<path d="M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4a2 2 0 0 0 1-1.7z"/><path d="M3.3 7L12 12l8.7-5M12 22V12"/>',
        pin: '<path d="M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
        heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z"/>',
        clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        star: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
        cal: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
        fire: '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.4-.5-2-1-3-1.1-2.1-.2-4 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.2.4-2.3 1-3.3.3 1.3 1.2 2.8 2.5 2.8z"/>',
    };
    function ic(name) { return '<svg class="ic" viewBox="0 0 24 24">' + (I[name] || '') + '</svg>'; }
    var LOGO = '<svg viewBox="0 0 24 24"><rect x="4" y="3.5" width="11" height="15" rx="2" fill="#6b5320" transform="rotate(-10 9.5 11)"/>' +
        '<rect x="8" y="5" width="11" height="15" rx="2" fill="url(#g)"/><path d="M13.5 9.5l1 2.1 2.3.3-1.7 1.6.4 2.3-2-1.1-2 1.1.4-2.3-1.7-1.6 2.3-.3z" fill="#1a1200"/>' +
        '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#d98c1f"/></linearGradient></defs></svg>';

    var FALLBACK = '../img/items/ascard_player.png';
    function imgSrc(t) {
        t = t || {};
        if (t.cardId) return (t.graded ? '../img/slabs/' : '../img/cards/') + encodeURIComponent(t.cardId) + '.webp';
        if (t.item) return '../img/items/' + encodeURIComponent(t.item) + '.png';
        return FALLBACK;
    }
    function img(t, cls) {
        return '<img loading="lazy" src="' + imgSrc(t) + '" onerror="this.onerror=null;this.src=\'' + FALLBACK + '\'" alt="">';
    }
    function thumbTags(t) {
        t = t || {};
        var s = '';
        if (t.graded) s += '<span class="tag gold">PSA ' + esc(t.grade) + '</span>';
        if (t.insert) s += '<span class="tag gold">' + esc(t.insert) + '</span>';
        if (t.parallel) s += '<span class="tag blue">' + esc(t.parallel) + '</span>';
        if (t.foil) s += '<span class="tag blue">Foil</span>';
        if (t.error) s += '<span class="tag red">Error</span>';
        if (t.rookie) s += '<span class="tag">RC</span>';
        return s;
    }

    // ------------------------------------------------------------------ state
    var S = {
        tab: 'market',
        stack: [],          // [{ name, params }]
        view: null,         // { name, params, data }
        home: null,
        q: { prices: { search: '', type: '', sort: 'price', page: 1 }, auctions: { search: '', kind: '', sort: 'ending', page: 1 } },
        seg: { auctions: 'browse', mine: 'selling', collection: 'mycards', check: '' },
        checklist: { set: null, filter: 'all', type: '' },
        checkResult: null,
        sheet: null,
        loading: false,
        toastTimer: null,
    };

    function call(name, args) { return ASC.call(name, args || {}); }

    function toast(text, err) {
        var el = document.getElementById('toast');
        if (!el) { el = document.createElement('div'); el.id = 'toast'; el.className = 'toast'; document.body.appendChild(el); }
        el.textContent = text;
        el.className = 'toast show' + (err ? ' err' : '');
        clearTimeout(S.toastTimer);
        S.toastTimer = setTimeout(function () { el.className = 'toast' + (err ? ' err' : ''); }, 2800);
    }

    // ------------------------------------------------------------------ views
    var V = {};

    /* ----- MARKET (price guide) ----- */
    V.market = {
        title: 'Price guide', tab: 'market',
        load: function () {
            var q = S.q.prices;
            return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('prices', q)]).then(function (r) {
                S.home = r[0]; setNow(r[0].now);
                return { prices: r[1] };
            });
        },
        html: function (d) {
            var h = S.home, q = S.q.prices, out = '<div class="pad">';
            var first = q.page === 1 && !q.search && !q.type;
            if (!SITE) out += '<h1 class="ttl">Price guide</h1>';
            if (first) {
                out += '<div class="hero"><div class="k">LS Card Exchange</div><div class="v">Live card market</div>' +
                    '<div class="s">Guide prices are for a plain mint card. Prices move with how many copies exist and what players pay at auction. Your own cards and their real values are under Collection → My cards.</div>' +
                    '<div class="stats"><div><b class="num">' + (h.auctions.enabled ? h.auctions.live : '—') + '</b><span>Live auctions</span></div>' +
                    '<div><b class="num">' + d.prices.total + '</b><span>Cards tracked</span></div>' +
                    '<div><b>' + (h.updatedAt ? ago(h.updatedAt) : '—') + '</b><span>Last update</span></div></div>' +
                    '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px;position:relative;z-index:1"><button class="btn sm" data-act="odds">Pack odds</button><button class="btn sm ghost" data-act="week">This week</button>' +
                    '<button class="btn sm ghost" data-act="drops">Release days</button></div></div>';
                if (h.drops && (h.drops.live || h.drops.upcoming)) {
                    out += '<div class="panel list" style="margin-top:12px"><div class="li" data-act="drops"><div class="main"><div class="name">' + ic('cal') + ' ' + (h.drops.live ? h.drops.live + ' release' + (h.drops.live > 1 ? 's' : '') + ' on sale now' : h.drops.upcoming + ' release' + (h.drops.upcoming > 1 ? 's' : '') + ' coming soon') +
                        '</div><div class="sub">Limited products. Tap to see them.</div></div>' + (h.drops.live ? '<span class="tag green">Live</span>' : '<span class="tag gold">Soon</span>') + '</div></div>';
                }
                if (h.movers.up.length || h.movers.down.length) {
                    out += '<h2 class="sec">Biggest movers <span class="muted small">7 days</span></h2><div class="movers">';
                    var m = h.movers.up.slice(0, 3).concat(h.movers.down.slice(0, 3));
                    m.forEach(function (c) {
                        out += '<div class="mover" data-act="card" data-id="' + esc(c.id) + '">' + img({ cardId: c.id }) +
                            '<div style="min-width:0"><div class="n">' + esc(c.name) + '</div><div class="p num">' + money(c.price) + ' ' + pct(c.change) + '</div></div></div>';
                    });
                    out += '</div>';
                }
                if (h.sealed.length) {
                    out += '<h2 class="sec">Sealed product' + (h.nextRestock ? ' <span class="muted small">restock in ' + timer(h.nextRestock) + '</span>' : '') + '</h2><div class="panel list">';
                    h.sealed.forEach(function (s) {
                        out += '<div class="li" style="cursor:default"><div class="th sealed">' + img({ item: s.item }) + '</div><div class="main"><div class="name">' + esc(s.label) +
                            '</div><div class="sub">Shop ' + money(s.shop) + ' · Card shop pays ' + money(s.buyer) + (s.left === 0 ? ' · <span class="down">Sold out</span>' : (s.left != null ? ' · ' + s.left + ' left this week' : '')) + '</div></div><div class="right"><div class="price num">' + money(s.value) +
                            '</div><div class="chg">' + pct(s.shop ? Math.round((s.value / s.shop - 1) * 1000) / 10 : 0) + '</div></div></div>';
                    });
                    out += '</div>';
                }
                out += '<h2 class="sec">All cards</h2>';
            }
            out += '<div class="search">' + ic('search') + '<input id="q-prices" type="search" placeholder="Player, club or card number" value="' + esc(q.search) + '"></div>';
            out += '<div class="chips"><button class="chip' + (q.type === '' ? ' on' : '') + '" data-act="ptype" data-v="">All</button>';
            h.types.forEach(function (t) { out += '<button class="chip' + (q.type === t.id ? ' on' : '') + '" data-act="ptype" data-v="' + esc(t.id) + '">' + esc(t.label) + '</button>'; });
            out += '</div><div class="row-ctl"><span class="muted small">' + d.prices.total + ' cards</span><select class="select" id="s-prices">' +
                opt('price', 'Most valuable', q.sort) + opt('cheap', 'Cheapest', q.sort) + opt('up', 'Rising', q.sort) + opt('down', 'Falling', q.sort) + opt('number', 'Card number', q.sort) + opt('name', 'Name', q.sort) + '</select></div>';
            if (!d.prices.rows.length) out += emptyBox('search', 'No cards match that search.');
            else {
                out += '<div class="panel list">';
                d.prices.rows.forEach(function (c) {
                    out += '<div class="li" data-act="card" data-id="' + esc(c.id) + '"><div class="th">' + img({ cardId: c.id }) + '</div><div class="main"><div class="name">' + esc(c.name) +
                        (c.rookie ? '<span class="tag">RC</span>' : '') + '</div><div class="sub">#' + esc(c.code) + ' · ' + esc(c.typeLabel) + ' · ' + esc(c.club) + '</div></div>' +
                        '<div class="right"><div class="price num">' + money(c.price) + '</div><div class="chg">' + pct(c.change) + '</div></div></div>';
                });
                out += '</div>' + pager(d.prices, 'ppage');
            }
            return out + '</div>';
        },
    };

    function opt(v, label, cur) { return '<option value="' + v + '"' + (v === cur ? ' selected' : '') + '>' + esc(label) + '</option>'; }
    function emptyBox(icon, text) { return '<div class="empty">' + ic(icon) + '<div>' + esc(text) + '</div></div>'; }
    function pager(d, act) {
        if (d.pages <= 1) return '';
        return '<div class="pager"><button class="btn ghost sm" data-act="' + act + '" data-v="' + (d.page - 1) + '"' + (d.page <= 1 ? ' disabled' : '') + '>Previous</button>' +
            '<span class="num">Page ' + d.page + ' of ' + d.pages + '</span><button class="btn ghost sm" data-act="' + act + '" data-v="' + (d.page + 1) + '"' + (d.page >= d.pages ? ' disabled' : '') + '>Next</button></div>';
    }

    function chart(points, emptyMsg) {
        if (!points || points.length < 2) return '<div class="chart"><div class="muted small" style="padding:30px 0;text-align:center">' + esc(emptyMsg || 'Not enough history yet. Prices are saved every hour.') + '</div></div>';
        var W = 320, H = 150, P = 6;
        var xs = points.map(function (p) { return p[0]; }), ys = points.map(function (p) { return p[1]; });
        var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs), y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
        if (y1 === y0) { y1 += 1; y0 = Math.max(0, y0 - 1); }
        var pad = (y1 - y0) * 0.12; y0 -= pad; y1 += pad;
        function X(v) { return P + (x1 === x0 ? 0 : (v - x0) / (x1 - x0)) * (W - 2 * P); }
        function Y(v) { return H - P - (v - y0) / (y1 - y0) * (H - 2 * P); }
        var line = points.map(function (p, i) { return (i ? 'L' : 'M') + X(p[0]).toFixed(1) + ' ' + Y(p[1]).toFixed(1); }).join(' ');
        var area = line + ' L' + X(x1).toFixed(1) + ' ' + (H - P) + ' L' + X(x0).toFixed(1) + ' ' + (H - P) + ' Z';
        var upTrend = ys[ys.length - 1] >= ys[0];
        var col = upTrend ? 'var(--up)' : 'var(--down)';
        var last = points[points.length - 1];
        return '<div class="chart"><svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
            '<defs><linearGradient id="cg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + (upTrend ? '#1f9d55' : '#d93b3b') + '" stop-opacity=".25"/><stop offset="1" stop-color="' + (upTrend ? '#1f9d55' : '#d93b3b') + '" stop-opacity="0"/></linearGradient></defs>' +
            '<path d="' + area + '" fill="url(#cg)"/><path d="' + line + '" fill="none" stroke="' + col + '" stroke-width="2.2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>' +
            '<circle cx="' + X(last[0]).toFixed(1) + '" cy="' + Y(last[1]).toFixed(1) + '" r="3.5" fill="' + col + '"/></svg>' +
            '<div class="lab"><span>' + dateStr(x0) + '</span><span>Low ' + money(Math.min.apply(null, ys)) + ' · High ' + money(Math.max.apply(null, ys)) + '</span><span>Now</span></div></div>';
    }

    /* ----- CARD DETAIL ----- */
    V.card = {
        title: 'Card', tab: 'market',
        load: function (p) { return call('card', { id: p.id }); },
        html: function (c) {
            var out = '<div class="pad"><div class="detail-top"><div class="detail-img">' + img({ cardId: c.id }) + '</div><div style="min-width:0">' +
                '<div class="muted small">#' + esc(c.code) + ' · ' + esc(c.setLabel || '') + '</div><div style="font-size:22px;font-weight:800;letter-spacing:-.02em;margin:2px 0 4px">' + esc(c.name) +
                (c.rookie ? '<span class="tag">RC</span>' : '') + '</div><div class="muted small">' + esc(c.typeLabel) + ' · ' + esc(c.club) + (c.pos ? ' · ' + esc(c.pos) : '') + '</div>' +
                '<div class="bigprice num" style="margin-top:10px">' + money(c.price) + '</div><div class="small">' + pct(c.change) + ' <span class="muted">this week</span></div></div></div>';
            out += '<div class="panel" style="margin-top:14px">' + chart(c.history) + '</div>';
            out += '<div class="kv"><div><span>Copies pulled</span><b class="num">' + c.printed + (c.maxPrints ? ' / ' + c.maxPrints : '') + '</b></div>' +
                '<div><span>Average for ' + esc(c.typeLabel) + '</span><b class="num">' + c.avgPrinted + '</b></div>' +
                '<div><span>Supply effect</span><b class="num ' + (c.supply >= 1 ? 'up' : 'down') + '">×' + c.supply.toFixed(2) + '</b></div>' +
                '<div><span>Demand (' + c.salesCounted + ' sales)</span><b class="num ' + (c.demand >= 1 ? 'up' : 'down') + '">×' + c.demand.toFixed(2) + '</b></div></div>';
            if (c.soldOut) out += '<div class="notice warn">Sold out: every copy of this card has been pulled. No more will ever come out of packs.</div>';
            out += '<div class="grid2" style="margin-top:12px"><button class="btn dark" data-act="cardAuctions" data-id="' + esc(c.id) + '">' + ic('gavel') + ' Auctions' + (c.liveAuctions ? ' (' + c.liveAuctions + ')' : '') + '</button>' +
                '<button class="btn ghost" data-act="alertNew" data-id="' + esc(c.id) + '" data-name="' + esc(c.name) + '" data-price="' + c.price + '">' + ic('bell') + ' Price alert</button></div>' +
                '<button class="btn block ' + (c.wanted ? 'want-on' : 'ghost') + '" style="margin-top:10px" data-act="want" data-id="' + esc(c.id) + '">' + ic('heart') + (c.wanted ? ' On your wantlist' : ' Add to wantlist') + '</button>' +
                '<div class="muted small" style="margin-top:6px">Wantlist: your phone pings when this card is put up for auction.</div>';
            out += '<h2 class="sec">Every version</h2><div class="panel"><table class="table">';
            c.variants.forEach(function (v) { out += '<tr><td>' + esc(v.label) + '</td><td class="num">' + money(v.price) + '</td></tr>'; });
            out += '</table></div><div class="muted small" style="margin-top:6px">Raw prices are for a mint card. Wear, dings and creases bring the value down.</div>';
            out += popHtml(c.pop);
            out += '<h2 class="sec">Recent sales</h2>';
            if (!c.sales.length) out += '<div class="panel">' + emptyBox('tag', 'No auction sales yet.') + '</div>';
            else {
                out += '<div class="panel"><table class="table">';
                c.sales.forEach(function (s) { out += '<tr><td><div style="font-weight:600">' + esc(s.title) + '</div><div class="muted small">' + ago(s.at) + '</div></td><td class="num">' + money(s.price) + '</td></tr>'; });
                out += '</table></div>';
            }
            return out + '</div>';
        },
    };

    function popHtml(p) {
        var out = '<h2 class="sec">Population report <span class="muted small">' + (p ? p.total : 0) + ' graded</span></h2>';
        if (!p || !p.total) return out + '<div class="panel">' + emptyBox('shield', 'None of this card have been graded yet.') + '</div>';
        out += '<div class="panel" style="overflow-x:auto"><table class="table pop"><tr><td class="muted small">Version</td>';
        [10, 9, 8, 7, 6, 5].forEach(function (g) { out += '<td class="muted small">' + g + '</td>'; });
        out += '<td class="muted small">≤4</td><td class="muted small">Total</td></tr>';
        p.rows.forEach(function (r) {
            out += '<tr><td style="font-weight:650">' + esc(r.label) + '</td>';
            [10, 9, 8, 7, 6, 5].forEach(function (g) { var n = gradeCount(r.grades, g); out += '<td class="num' + (g === 10 && n ? ' up' : '') + '">' + (n || '–') + '</td>'; });
            var low = 0; for (var k = 1; k <= 4; k++) low += gradeCount(r.grades, k);
            out += '<td class="num">' + (low || '–') + '</td><td class="num">' + r.total + '</td></tr>';
        });
        return out + '</table></div><div class="muted small" style="margin-top:6px">Every copy ever graded, like a real pop report. Cracked slabs stay on the report.</div>';
    }
    // grades come from a Lua list (1..10), which JSON turns into [g1..g10]
    function gradeCount(grades, g) { if (Array.isArray(grades)) return grades[g - 1] || 0; return (grades && (grades[g] || grades[String(g)])) || 0; }

    /* ----- PACK ODDS ----- */
    V.odds = {
        title: 'Pack odds', tab: SITE ? 'odds' : 'market',
        load: function () { return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('odds')]).then(function (r) { S.home = r[0]; setNow(r[0].now); return r[1]; }); },
        html: function (o) {
            var out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Pack odds</h1>';
            out += '<div class="notice">Official odds for every product. "1 in X packs" is an average: you could pull it first time, or never.</div>';
            if (o.stock && o.stock.items.length) {
                out += '<h2 class="sec">This week’s stock <span class="muted small">restock in ' + timer(o.stock.nextRestock) + '</span></h2><div class="panel list">';
                o.stock.items.forEach(function (x) {
                    out += '<div class="li" style="cursor:default"><div class="th sealed">' + img({ item: x.item }) + '</div><div class="main"><div class="name">' + esc(x.label) + '</div><div class="sub">' + money(x.price) + '</div></div><div class="right">' +
                        (x.left > 0 ? '<div class="price num">' + x.left + ' / ' + x.max + '</div><div class="chg muted">left</div>' : '<span class="tag red">Sold out</span>') + '</div></div>';
                });
                out += '</div>';
            }
            out += '<h2 class="sec">Packs</h2>';
            o.packs.forEach(function (p) {
                out += '<div class="panel list" style="margin-bottom:12px"><div class="li" style="cursor:default;border-bottom:1px solid var(--line)"><div class="th sealed">' + img({ item: p.item }) + '</div><div class="main"><div class="name">' + esc(p.label) + '</div><div class="sub">' +
                    p.cards + ' cards' + (p.price ? ' · ' + money(p.price) : '') + (p.guaranteed ? ' · ' + esc(p.guaranteed) : '') + '</div></div></div><table class="table">';
                p.types.forEach(function (t) { out += '<tr><td>' + esc(t.label) + '</td><td class="num">' + t.pct + '% per card</td></tr>'; });
                out += '<tr><td>Foil</td><td>' + esc(p.foil) + '</td></tr>';
                if (p.parallelGuaranteed) out += '<tr><td>Numbered parallel</td><td>1 guaranteed</td></tr>';
                (p.parallels || []).forEach(function (x) { if (x.perPack) out += '<tr><td>' + esc(x.label) + '</td><td class="num">1 in ' + x.perPack.toLocaleString('en-GB') + ' packs</td></tr>'; });
                if (p.hit) out += '<tr><td>Autograph / relic hit</td><td class="num">1 in ' + p.hit.toLocaleString('en-GB') + ' packs</td></tr>';
                if (p.error) out += '<tr><td>Error card</td><td class="num">1 in ' + p.error.toLocaleString('en-GB') + ' packs</td></tr>';
                out += '</table></div>';
            });
            if (o.boxes.length) {
                out += '<h2 class="sec">Boxes and tins</h2><div class="panel list">';
                o.boxes.forEach(function (b) {
                    out += '<div class="li" style="cursor:default"><div class="th sealed">' + img({ item: b.item }) + '</div><div class="main"><div class="name">' + esc(b.label) + '</div><div class="sub" style="white-space:normal">' + esc(b.contents) +
                        (b.hits ? ' · ' + b.hits + ' guaranteed hit' + (b.hits > 1 ? 's' : '') : '') + (b.bonus ? ' · ' + esc(b.bonus) : '') + (b.caseHit ? ' · <b class="up">Case hit: about 1 in ' + b.caseHit + ' boxes</b>' : '') + '</div></div><div class="right">' + (b.price ? '<div class="price num">' + money(b.price) + '</div>' : '') + '</div></div>';
                });
                out += '</div>';
            }
            if (o.inserts.length) {
                out += '<h2 class="sec">When you pull a hit</h2><div class="panel"><table class="table">';
                o.inserts.forEach(function (x) { out += '<tr><td>' + esc(x.label) + ' <span class="muted small">/' + x.max + '</span></td><td class="num">' + x.share + '% of hits</td></tr>'; });
                out += '</table></div>';
            }
            return out + '</div>';
        },
    };

    /* ----- AUCTIONS ----- */
    var KINDS = [['', 'All'], ['card', 'Raw'], ['graded', 'Graded'], ['insert', 'Hits'], ['parallel', 'Parallels'], ['sealed', 'Sealed'], ['lot', 'Lots']];
    function ratingHtml(r) {
        if (!r || !r.count) return '<span class="muted">New seller</span>';
        return '<span class="' + (r.pct >= 90 ? 'up' : r.pct >= 70 ? '' : 'down') + '">' + r.pct + '% positive</span> <span class="muted">(' + r.count + ')</span>';
    }
    function auctionRow(a) {
        var price = a.bid ? money(a.bid) : money(a.start);
        var sub = a.bids ? (a.bids + (a.bids === 1 ? ' bid' : ' bids')) : 'No bids';
        var tags = '';
        if (a.buyNow) tags += '<span class="tag green">Buy ' + money(a.buyNow) + '</span>';
        if (a.hasReserve && !a.reserveMet) tags += '<span class="tag">Reserve</span>';
        if (a.winning) tags += '<span class="tag green">Winning</span>';
        if (a.yours) tags += '<span class="tag gold">Yours</span>';
        if (a.lotCount) tags += '<span class="tag blue">Lot · ' + a.lotCount + '</span>';
        if (a.offerCount) tags += '<span class="tag green">' + a.offerCount + (a.offerCount === 1 ? ' offer' : ' offers') + '</span>';
        if (a.offerAmount) tags += '<span class="tag green">Your offer ' + money(a.offerAmount) + '</span>';
        if (a.status && a.status !== 'live') {
            var st = { sold: a.won ? 'Won' : 'Sold', unsold: 'Not sold', cancelled: 'Cancelled' }[a.status] || a.status;
            return '<div class="li" data-act="auction" data-id="' + a.id + '"><div class="th' + (a.kind === 'sealed' ? ' sealed' : '') + '">' + img(a.thumb) + '</div><div class="main"><div class="name">' + esc(a.title) +
                '</div><div class="sub">' + esc(st) + ' · ' + ago(a.endsAt) + (a.rated != null ? ' · <span class="up">Rated</span>' : '') + '</div></div><div class="right"><div class="price num">' + (a.finalPrice ? money(a.finalPrice) : '—') + '</div>' +
                (a.canRate ? '<button class="btn sm" style="margin-top:4px" data-act="rateOpen" data-id="' + a.id + '">Rate seller</button>' : '') + '</div></div>';
        }
        return '<div class="li" data-act="auction" data-id="' + a.id + '"><div class="th' + (a.kind === 'sealed' ? ' sealed' : '') + '">' + img(a.thumb) + '</div><div class="main"><div class="name">' + esc(a.title) +
            '</div><div class="sub">' + thumbTags(a.thumb) + ' ' + sub + tags + '</div></div><div class="right"><div class="price num">' + price + '</div><div class="chg">' + timer(a.endsAt) + '</div></div></div>';
    }

    V.auctions = {
        title: 'Auctions', tab: 'auctions', poll: true,
        load: function (p) {
            var q = S.q.auctions;
            var args = { search: q.search, kind: q.kind, sort: q.sort, page: q.page };
            if (p && p.cardId) args.cardId = p.cardId;
            return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('auctions', args)]).then(function (r) {
                S.home = r[0]; setNow(r[1].now); return r[1];
            });
        },
        html: function (d, p) {
            var q = S.q.auctions, out = '<div class="pad">';
            if (!SITE && !(p && p.cardId)) out += '<h1 class="ttl">Auctions</h1>';
            if (!(p && p.cardId)) {
                out += '<div class="seg"><button class="on">Browse</button><button data-act="goto" data-v="mine">My auctions</button></div>';
                out += '<div class="search">' + ic('search') + '<input id="q-auctions" type="search" placeholder="Search auctions" value="' + esc(q.search) + '"></div>';
                out += '<div class="chips">';
                KINDS.forEach(function (k) { out += '<button class="chip' + (q.kind === k[0] ? ' on' : '') + '" data-act="akind" data-v="' + k[0] + '">' + k[1] + '</button>'; });
                out += '</div>';
                out += '<div class="row-ctl"><span class="muted small">' + d.total + ' live</span><select class="select" id="s-auctions">' +
                    opt('ending', 'Ending soonest', q.sort) + opt('new', 'Newly listed', q.sort) + opt('low', 'Lowest price', q.sort) + opt('high', 'Highest price', q.sort) + opt('bids', 'Most bids', q.sort) + '</select></div>';
            } else {
                out += '<div class="muted small" style="margin-bottom:10px">Live auctions for this card</div>';
            }
            if (!d.rows.length) out += '<div class="panel">' + emptyBox('gavel', 'No live auctions right now. List a card from the Sell tab.') + '</div>';
            else out += '<div class="panel list">' + d.rows.map(auctionRow).join('') + '</div>' + pager(d, 'apage');
            return out + '</div>';
        },
    };

    V.auction = {
        title: 'Auction', tab: 'auctions', poll: true,
        load: function (p) {
            return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('auction', { id: p.id })]).then(function (r) { S.home = r[0]; setNow(r[1].now); return r[1]; });
        },
        html: function (a) {
            var live = a.status === 'live' && a.endsAt > now();
            var out = '<div class="pad"><div class="detail-img big">' + img(a.thumb) + '</div>';
            out += '<div style="margin:14px 0 4px;font-size:20px;font-weight:800;letter-spacing:-.02em">' + esc(a.title) + '</div>';
            out += '<div class="small muted">' + (a.lot ? '' : thumbTags(a.thumb)) + ' Sold by <a class="link" data-act="seller" data-id="' + a.id + '">' + esc(a.seller) + '</a> · ' + ratingHtml(a.sellerRating) + (a.serial ? ' · ' + esc(a.serial) : '') + '</div>';
            if (a.stolen) out += '<div class="notice bad">This serial has been reported stolen.</div>';
            out += '<div class="panel bidbox" style="margin-top:12px">';
            if (live) {
                out += '<div class="cur"><div><div class="muted small">' + (a.bid ? 'Current bid' : 'Starting price') + '</div><b class="num">' + money(a.bid || a.start) + '</b></div>' +
                    '<div style="text-align:right"><div class="muted small">Ends in</div>' + timer(a.endsAt) + '</div></div>';
                out += '<div class="small muted" style="margin-top:6px">' + (a.bids ? a.bids + (a.bids === 1 ? ' bid' : ' bids') : 'No bids yet') +
                    (a.hasReserve ? (a.reserveMet ? ' · <span class="up">Reserve met</span>' : ' · Reserve not met') : '') + '</div>';
                if (a.winning) out += '<div class="notice good">You’re the highest bidder.</div>';
                if (a.yours) {
                    out += '<div class="notice">This is your auction.</div>';
                    if (a.offers && a.offers.length) {
                        out += '<div class="small" style="font-weight:700;margin:4px 0 6px">Offers waiting</div><div class="panel list" style="box-shadow:none;background:var(--card2);margin-bottom:10px">';
                        a.offers.forEach(function (o) {
                            out += '<div class="li" style="cursor:default"><div class="main"><div class="name num">' + money(o.amount) + '</div><div class="sub">' + esc(o.name) + ' · ' + ago(o.at) + '</div></div>' +
                                '<button class="btn sm" data-act="offerAnswer" data-id="' + o.id + '" data-v="1" data-amount="' + o.amount + '">Accept</button> <button class="btn sm ghost" style="margin-left:6px" data-act="offerAnswer" data-id="' + o.id + '" data-v="0" data-amount="' + o.amount + '">Decline</button></div>';
                        });
                        out += '</div>';
                    }
                    if (!a.bids) out += '<button class="btn danger block" data-act="cancel" data-id="' + a.id + '">Cancel auction</button>';
                } else {
                    out += '<div class="line"><label class="money-in"><input class="input num" id="bid-amt" type="number" inputmode="numeric" min="' + a.minNext + '" value="' + a.minNext + '"></label>' +
                        '<button class="btn" data-act="bid" data-id="' + a.id + '">Bid</button></div>';
                    out += '<div class="muted small" style="margin-top:6px">Enter ' + money(a.minNext) + ' or more. Your bid is taken from your ' + esc(S.home.account) + ' now and given back if you’re outbid.</div>';
                    if (a.buyNow) out += '<button class="btn dark block" style="margin-top:10px" data-act="buyNow" data-id="' + a.id + '" data-price="' + a.buyNow + '">Buy it now · ' + money(a.buyNow) + '</button>';
                    if (a.canOffer) {
                        out += '<button class="btn ghost block" style="margin-top:8px" data-act="offerOpen" data-id="' + a.id + '" data-min="' + a.minOffer + '" data-bin="' + a.buyNow + '" data-mine="' + (a.myOffer || '') + '">' +
                            (a.myOffer ? 'Change your offer (' + money(a.myOffer) + ')' : 'Make an offer') + '</button>';
                        if (a.myOffer) out += '<div class="muted small" style="margin-top:6px">Your ' + money(a.myOffer) + ' offer is waiting for the seller. The money is held and comes back if they decline.</div>';
                    }
                }
            } else {
                var st = { sold: 'Sold', unsold: 'Not sold', cancelled: 'Cancelled' }[a.status] || 'Ended';
                out += '<div class="cur"><div><div class="muted small">' + st + '</div><b class="num">' + (a.finalPrice ? money(a.finalPrice) : '—') + '</b></div></div>';
            }
            out += '</div>';
            if (live && !a.yours) {
                out += '<div class="grid2" style="margin-top:10px"><button class="btn ghost" data-act="watch" data-id="' + a.id + '">' + ic('eye') + (a.watching ? ' Watching' : ' Watch') + '</button>' +
                    '<button class="btn ghost" data-act="lockers">' + ic('pin') + ' Delivery</button></div>';
                out += '<div class="muted small" style="margin-top:8px">If you win, it’s sent to ' + esc(lockerLabel()) + '.</div>';
            }
            if (a.lot) {
                out += '<h2 class="sec">In this lot <span class="muted small">' + a.lot.length + ' items</span></h2><div class="panel list">';
                a.lot.forEach(function (it) {
                    out += '<div class="li"' + (it.cardId ? ' data-act="card" data-id="' + esc(it.cardId) + '"' : ' style="cursor:default"') + '><div class="th' + (it.kind === 'sealed' ? ' sealed' : '') + '">' + img(it.thumb) + '</div><div class="main"><div class="name">' + esc(it.title) +
                        '</div><div class="sub">' + thumbTags(it.thumb) + '</div></div><div class="right"><div class="price num">' + money(it.value) + '</div></div></div>';
                });
                out += '</div>';
            }
            out += '<div class="kv">';
            if (a.value) out += '<div><span>' + (a.lot ? 'Market value (all)' : 'Market value') + '</span><b class="num">' + money(a.value) + '</b></div>';
            if (a.grade) out += '<div><span>Grade</span><b>' + esc(a.grade.grade) + ' ' + esc(a.grade.label || '') + '</b></div>';
            if (a.condition) out += '<div><span>Condition</span><b>' + esc(a.condition.glance) + '</b></div>';
            if (a.condition && a.condition.prot) out += '<div><span>Protection</span><b>' + esc(a.condition.prot) + '</b></div>';
            if (a.print) out += '<div><span>Print</span><b class="num">#' + a.print + (a.maxPrints ? ' / ' + a.maxPrints : '') + '</b></div>';
            if (a.grade && a.grade.cert) out += '<div><span>Cert</span><b class="num">' + esc(a.grade.cert) + '</b></div>';
            if (a.pop && a.pop.total) out += '<div><span>Pop at this grade</span><b class="num">' + a.pop.same + (a.pop.higher ? ' · ' + a.pop.higher + ' higher' : ' · none higher') + '</b></div>';
            out += '</div>';
            if (a.grade && a.grade.sub) {
                var s = a.grade.sub;
                out += '<h2 class="sec">Sub-grades</h2><div class="kv"><div><span>Centering</span><b>' + esc(s.cen) + '</b></div><div><span>Corners</span><b>' + esc(s.cor) +
                    '</b></div><div><span>Edges</span><b>' + esc(s.edg) + '</b></div><div><span>Surface</span><b>' + esc(s.sur) + '</b></div></div>';
            }
            if (a.thumb && a.thumb.cardId) out += '<button class="btn ghost block" style="margin-top:12px" data-act="card" data-id="' + esc(a.thumb.cardId) + '">' + ic('chart') + ' Price guide for this card</button>';
            out += '<h2 class="sec">Bid history</h2>';
            if (!a.history.length) out += '<div class="panel">' + emptyBox('gavel', 'No bids yet.') + '</div>';
            else {
                out += '<div class="panel"><table class="table">';
                a.history.forEach(function (b) { out += '<tr><td><div style="font-weight:600">' + esc(b.name) + '</div><div class="muted small">' + ago(b.at) + '</div></td><td class="num">' + money(b.amount) + '</td></tr>'; });
                out += '</table></div>';
            }
            return out + '</div>';
        },
    };

    function lockerLabel() {
        var h = S.home || {};
        if (!h.postal) return 'your pockets (next time you’re online)';
        var l = (h.lockers || []).filter(function (x) { return x.id === h.locker; })[0] || (h.lockers || [])[0];
        return l ? 'Postal Prime locker: ' + l.label : 'a Postal Prime locker';
    }

    V.mine = {
        title: 'My auctions', tab: 'auctions', poll: true,
        load: function () { return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('mine')]).then(function (r) { S.home = r[0]; setNow(r[1].now); return r[1]; }); },
        html: function (d) {
            var seg = S.seg.mine, out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Auctions</h1>';
            out += '<div class="seg"><button data-act="goto" data-v="auctions">Browse</button><button class="on">My auctions</button></div>';
            out += '<div class="chips" style="padding-top:0;margin-bottom:10px">';
            [['selling', 'Selling', d.selling.length], ['bidding', 'Bidding', d.bidding.length], ['offers', 'Offers', (d.offers || []).length], ['watching', 'Watching', d.watching.length], ['ended', 'Finished', 0]].forEach(function (s) {
                out += '<button class="chip' + (seg === s[0] ? ' on' : '') + '" data-act="mseg" data-v="' + s[0] + '">' + s[1] + (s[2] ? ' · ' + s[2] : '') + '</button>';
            });
            out += '</div>';
            var list = d[seg] || [];
            var empty = { selling: 'You have nothing listed. Use the Sell tab.', bidding: 'You haven’t bid on anything that’s still live.', offers: 'You have no offers waiting. Make one on any buy it now listing.', watching: 'Tap Watch on an auction to keep an eye on it.', ended: 'Nothing finished yet.' }[seg];
            if (!list.length) out += '<div class="panel">' + emptyBox('gavel', empty) + '</div>';
            else out += '<div class="panel list">' + list.map(auctionRow).join('') + '</div>';
            out += '<h2 class="sec">Delivery <a data-act="lockers">Change</a></h2><div class="panel list"><div class="li" style="cursor:default"><div class="main"><div class="name">' + ic('pin') + ' ' + esc(lockerLabel()) +
                '</div><div class="sub">Wins, and your unsold or cancelled items, are sent here.</div></div></div></div>';
            if (d.deliveries.length) {
                out += '<h2 class="sec">Recent parcels</h2><div class="panel list">';
                d.deliveries.forEach(function (x) {
                    var st = { pending: 'Waiting to send', sent: 'At your locker soon', given: 'In your pockets', collected: 'Collected' }[x.status] || x.status;
                    out += '<div class="li" style="cursor:default"><div class="main"><div class="name">' + esc(x.title) + '</div><div class="sub">' + ({ returned: 'Returned to you · ', drop: 'Release day · ', appraisal: 'Appraisal letter · ' }[x.reason] || 'Won · ') + esc(st) + ' · ' + ago(x.at) + '</div></div></div>';
                });
                out += '</div>';
            }
            return out + '</div>';
        },
    };

    /* ----- SELL ----- */
    V.sell = {
        title: 'Sell', tab: 'sell',
        load: function () { return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('sellable')]).then(function (r) { S.home = r[0]; return r[1]; }); },
        html: function (d) {
            var out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Sell</h1>';
            var lotMode = !!S.lot;
            out += '<div class="seg"><button class="' + (lotMode ? '' : 'on') + '" data-act="lotMode" data-v="0">One item</button><button class="' + (lotMode ? 'on' : '') + '" data-act="lotMode" data-v="1">A lot (several)</button></div>';
            out += '<div class="notice">' + (lotMode ? 'Tick 2 to ' + (S.home.maxLot || 10) + ' items to sell together as one lot. The winner gets them all in one parcel.' :
                'Pick a card from your pockets to auction it.') + ' Items leave your pockets while the auction runs. If they don’t sell, they’re sent back to ' + esc(lockerLabel()) + '.</div>';
            if (!d.items.length) return out + '<div class="panel">' + emptyBox('tag', 'You have no cards or sealed product on you.') + '</div></div>';
            out += '<div class="panel list">';
            d.items.forEach(function (it, i) {
                var picked = lotMode && S.lot[it.slot];
                out += '<div class="li" data-act="sellPick" data-i="' + i + '"' + (it.stolen ? ' style="opacity:.5"' : '') + '>' + (lotMode ? '<span class="tick' + (picked ? ' on' : '') + '">' + (picked ? ic('check') : '') + '</span>' : '') +
                    '<div class="th' + (it.kind === 'sealed' ? ' sealed' : '') + '">' + img(it.thumb) + '</div><div class="main"><div class="name">' + esc(it.title) +
                    '</div><div class="sub">' + thumbTags(it.thumb) + (it.stolen ? '<span class="tag red">Reported stolen</span>' : '') + (it.count > 1 ? ' ×' + it.count : '') + '</div></div><div class="right"><div class="muted small">Worth about</div><div class="price num">' + money(it.value) + '</div></div></div>';
            });
            out += '</div>';
            if (lotMode) {
                var n = Object.keys(S.lot).length;
                out += '<div class="lotbar"><span>' + n + ' selected</span><button class="btn" data-act="lotGo"' + (n < 2 ? ' disabled' : '') + '>Create lot</button></div>';
            }
            return out + '</div>';
        },
    };

    function sellSheet(it, d, lot) {
        var dur = d.durations[1] || d.durations[0];
        S.sheet = { kind: 'sell', item: it, lot: lot, durations: d.durations, fvf: d.finalValueFee, dur: dur && dur.id };
        renderSheet();
    }

    /* ----- COLLECTION ----- */
    V.collection = {
        title: 'Collection', tab: 'collection',
        load: function () {
            var seg = S.seg.collection;
            if (seg === 'mycards') return call('portfolio').then(function (r) { return { portfolio: r }; });
            if (seg === 'stats') return call('stats').then(function (r) { return { stats: r }; });
            if (seg === 'pulls') return call('pulls').then(function (r) { return { pulls: r }; });
            if (seg === 'alerts') return Promise.all([call('alerts'), call('wants')]).then(function (r) { return { alerts: r[0], wants: r[1] }; });
            return call('checklist').then(function (r) { return { checklist: r }; });
        },
        html: function (d) {
            var seg = S.seg.collection, out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Collection</h1>';
            out += '<div class="seg">' + [['mycards', 'My cards'], ['checklist', 'Checklist'], ['stats', 'Stats'], ['pulls', 'Pulls'], ['alerts', 'Alerts']].map(function (s) {
                return '<button class="' + (seg === s[0] ? 'on' : '') + '" data-act="cseg" data-v="' + s[0] + '">' + s[1] + '</button>';
            }).join('') + '</div>';
            if (seg === 'mycards') out += portfolioHtml(d.portfolio);
            else if (seg === 'stats') out += statsHtml(d.stats);
            else if (seg === 'checklist') out += checklistHtml(d.checklist);
            else if (seg === 'pulls') out += pullsHtml(d.pulls);
            else out += alertsHtml(d.alerts) + wantsHtml(d.wants);
            return out + '</div>';
        },
    };

    function checklistHtml(c) {
        var cl = S.checklist;
        var set = c.sets.filter(function (s) { return s.id === cl.set; })[0] || c.sets[0];
        if (!set) return emptyBox('grid', 'No sets yet.');
        cl.set = set.id;
        var total = set.total, got = set.pulled, pctv = total ? got / total : 0;
        var C = 2 * Math.PI * 27;
        var out = '';
        if (c.sets.length > 1) {
            out += '<div class="chips" style="padding-top:0">' + c.sets.map(function (s) { return '<button class="chip' + (s.id === set.id ? ' on' : '') + '" data-act="clset" data-v="' + esc(s.id) + '">' + esc(s.label) + '</button>'; }).join('') + '</div>';
        }
        out += '<div class="panel prog"><svg class="ring" viewBox="0 0 64 64"><circle class="bgc" cx="32" cy="32" r="27"/><circle class="fgc" cx="32" cy="32" r="27" stroke-dasharray="' + C.toFixed(1) +
            '" stroke-dashoffset="' + (C * (1 - pctv)).toFixed(1) + '"/></svg><div><div style="font-size:22px;font-weight:800" class="num">' + got + ' / ' + total + '</div>' +
            '<div class="muted small">' + esc(set.label) + ' collected · ' + Math.round(pctv * 100) + '%</div><div class="small" style="margin-top:4px"><span class="up">● ' + set.have + ' on you</span> <span class="muted">● ' + (set.pulled - set.have) + ' pulled before</span></div></div></div>';
        out += '<div class="chips">' + [['all', 'All'], ['missing', 'Missing'], ['have', 'Pulled'], ['holding', 'On you']].map(function (f) {
            return '<button class="chip' + (cl.filter === f[0] ? ' on' : '') + '" data-act="clf" data-v="' + f[0] + '">' + f[1] + '</button>';
        }).join('') + '</div><div class="chips" style="padding-top:4px"><button class="chip' + (cl.type === '' ? ' on' : '') + '" data-act="clt" data-v="">Every type</button>' +
            c.types.map(function (t) { return '<button class="chip' + (cl.type === t.id ? ' on' : '') + '" data-act="clt" data-v="' + esc(t.id) + '">' + esc(t.label) + '</button>'; }).join('') + '</div>';
        var cards = set.cards.filter(function (x) {
            if (cl.type && x[3] !== cl.type) return false;
            if (cl.filter === 'missing') return !x[5];
            if (cl.filter === 'have') return !!x[5];
            if (cl.filter === 'holding') return !!x[6];
            return true;
        });
        if (!cards.length) return out + emptyBox('grid', 'Nothing here.');
        var shown = cards.slice(0, cl.limit || 120);
        out += '<div class="tiles" style="margin-top:10px">' + shown.map(function (x) {
            return '<div class="tile' + (x[5] ? '' : ' missing') + '" data-act="card" data-id="' + esc(x[0]) + '">' + (x[6] ? '<span class="dot h">✓</span>' : (x[5] ? '<span class="dot p">✓</span>' : '')) + (x[8] ? '<span class="wantdot">' + ic('heart') + '</span>' : '') +
                img({ cardId: x[0] }) + '<div class="c">#' + esc(x[1]) + ' · ' + esc(x[4]) + '</div><div class="n">' + esc(x[2]) + '</div><div class="c num">' + money(x[7]) + '</div></div>';
        }).join('') + '</div>';
        if (cards.length > shown.length) out += '<div class="pager"><button class="btn ghost sm" data-act="clmore">Show more (' + (cards.length - shown.length) + ' left)</button></div>';
        return out;
    }

    function portfolioHtml(p) {
        var out = '<div class="hero"><div class="k">Your collection</div><div class="v num">' + money(p.total + p.sealedTotal) + '</div>' +
            '<div class="s">What everything on you and in your binders is worth right now. The card shop pays these prices for cards (80% for sealed).</div>' +
            '<div class="stats"><div><b class="num">' + p.cards.length + '</b><span>Cards</span></div><div><b class="num">' + money(p.total) + '</b><span>Cards value</span></div>' +
            '<div><b class="num">' + money(p.sealedTotal) + '</b><span>Sealed</span></div></div></div>';
        out += '<h2 class="sec">Value over time</h2><div class="panel">' + chart(p.history, 'Your collection value is saved each day. Come back tomorrow to see the chart.') + '</div>';
        out += '<button class="btn ghost block" style="margin-top:12px" data-act="appraiseOpen">' + ic('shield') + ' Get an appraisal letter</button>';
        if (!p.cards.length && !p.sealed.length) return out + '<div class="panel" style="margin-top:12px">' + emptyBox('grid', 'You have no cards on you. Cards in a binder count too, as long as the binder is in your pockets.') + '</div>';
        if (p.cards.length) {
            out += '<h2 class="sec">Cards</h2><div class="panel list">';
            p.cards.forEach(function (c) {
                out += '<div class="li"' + (c.cardId ? ' data-act="card" data-id="' + esc(c.cardId) + '"' : '') + '><div class="th">' + img(c.thumb) + '</div><div class="main"><div class="name">' + esc(c.title) +
                    '</div><div class="sub">' + thumbTags(c.thumb) + ' ' + esc(c.where) + (c.condition ? ' · ' + esc(c.condition) : '') + '</div></div><div class="right"><div class="price num">' + money(c.value) + '</div></div></div>';
            });
            out += '</div>';
        }
        if (p.sealed.length) {
            out += '<h2 class="sec">Sealed</h2><div class="panel list">';
            p.sealed.forEach(function (c) {
                out += '<div class="li" style="cursor:default"><div class="th sealed">' + img(c.thumb) + '</div><div class="main"><div class="name">' + esc(c.title) + '</div><div class="sub">×' + c.count + '</div></div><div class="right"><div class="price num">' + money(c.value) + '</div></div></div>';
            });
            out += '</div>';
        }
        return out;
    }

    function statsHtml(st) {
        var ret = st.returnPct;
        var out = '<div class="hero"><div class="k">Your card stats</div><div class="v num">' + st.packs + ' packs opened</div><div class="s">' + st.cards + ' cards pulled' +
            (st.repacks ? ' · ' + st.repacks + ' repacks' : '') + (st.since ? ' · since ' + dateStr(st.since) : '') + '</div>' +
            '<div class="stats"><div><b class="num">' + money(st.spent) + '</b><span>Spent on product</span></div><div><b class="num">' + money(st.pulledValue) + '</b><span>Value pulled</span></div>' +
            '<div><b class="num ' + (ret == null ? '' : ret >= 100 ? 'up' : 'down') + '" style="color:' + (ret == null ? '#fff' : ret >= 100 ? '#6af0a0' : '#ff8a84') + '">' + (ret == null ? '—' : ret + '%') + '</b><span>Pack luck</span></div></div></div>';
        if (st.best) {
            out += '<h2 class="sec">Best pull</h2><div class="panel list"><div class="li"' + (st.best.cardId ? ' data-act="card" data-id="' + esc(st.best.cardId) + '"' : '') + '><div class="th">' + img({ cardId: st.best.cardId }) +
                '</div><div class="main"><div class="name">' + esc(st.best.title) + '</div><div class="sub">' + (st.best.at ? ago(st.best.at) : '') + '</div></div><div class="right"><div class="price num">' + money(st.best.value) + '</div><div class="chg muted">when pulled</div></div></div></div>';
        }
        out += '<h2 class="sec">Money</h2><div class="panel"><table class="table">' +
            '<tr><td>Spent on packs, boxes, repacks and releases</td><td class="num">' + money(st.spent) + '</td></tr>' +
            '<tr><td>Value of everything you pulled (at the time)</td><td class="num">' + money(st.pulledValue) + '</td></tr>' +
            '<tr><td>Sold to the card shop</td><td class="num">' + money(st.sold) + '</td></tr>' +
            '<tr><td>Earned from auctions (after fees)</td><td class="num">' + money(st.auctionEarned) + '</td></tr>' +
            '<tr><td>Spent at auctions</td><td class="num">' + money(st.auctionSpent) + '</td></tr></table></div>';
        out += '<div class="muted small" style="margin-top:6px">Pack luck = value pulled ÷ money spent on product. Over 100% means your pulls were worth more than you paid.</div>';
        return out;
    }

    /* ----- APPRAISAL ----- */
    V.appraise = {
        title: 'Appraisal letter', tab: 'collection',
        load: function () { return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('appraisable'), call('appraisals')]).then(function (r) { S.home = r[0]; r[1].letters = r[2]; return r[1]; }); },
        html: function (d) {
            var out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Appraisal letter</h1>';
            out += '<div class="notice">Get an official letter valuing one of your cards: the card, its serial number, condition or grade and today’s value. Handy for private sales and insurance. ' +
                money(d.price) + ' each. The letter is sent to ' + esc(lockerLabel()) + '. Your card stays with you.</div>';
            var L = d.letters || { list: [] };
            if (L.list.length) {
                var canPrint = SITE && L.printer;
                out += '<h2 class="sec">Your letters</h2><div class="panel list">' + L.list.map(function (a) {
                    return '<div class="li" style="cursor:default;flex-wrap:wrap"><div class="main"><div class="name">' + esc(a.title) + '</div><div class="sub">' + esc(a.ref) + ' · ' + esc(a.date) + ' · valued at ' + money(a.value) + '</div></div>' +
                        '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px">' + (L.phone ? '<button class="btn sm ghost" data-act="letterSave" data-id="' + esc(a.ref) + '">Save to phone</button>' : '') +
                        (L.computer ? '<button class="btn sm ghost" data-act="letterSaveComputer" data-id="' + esc(a.ref) + '">Save to computer</button>' : '') +
                        (canPrint ? '<button class="btn sm" data-act="letterPrint" data-id="' + esc(a.ref) + '">Print</button>' : '') + '</div></div>';
                }).join('') + '</div>' + (SITE ? '' : '<div class="muted small" style="margin-top:6px">To print a letter, save it to your computer and print it from File Explorer, or open lscardexchange.co.uk near a printer.</div>');
                out += '<h2 class="sec">Order a new letter</h2>';
            }
            if (!d.items.length) return out + '<div class="panel">' + emptyBox('shield', 'You have no cards on you.') + '</div></div>';
            out += '<div class="panel list">' + d.items.map(function (it, i) {
                return '<div class="li" data-act="appraiseGo" data-i="' + i + '"><div class="th">' + img(it.thumb) + '</div><div class="main"><div class="name">' + esc(it.title) + '</div><div class="sub">' + thumbTags(it.thumb) + '</div></div>' +
                    '<div class="right"><div class="muted small">About</div><div class="price num">' + money(it.value) + '</div></div></div>';
            }).join('') + '</div>';
            return out + '</div>';
        },
    };

    function pullsHtml(list) {
        var out = '<div class="notice">Cards you pulled from packs. If one is stolen, report it here: shops, graders and the auction house will refuse it.</div>';
        if (!list.length) return out + '<div class="panel">' + emptyBox('box', 'You haven’t pulled any cards yet.') + '</div>';
        out += '<div class="panel list">';
        list.forEach(function (p) {
            out += '<div class="li" style="cursor:default"><div class="th">' + img({ cardId: p.cardId }) + '</div><div class="main"><div class="name">' + esc(p.name) + '</div><div class="sub num">' + esc(p.serial) +
                (p.stolen ? '<span class="tag red">Reported stolen</span>' : '') + '</div></div><button class="btn sm ' + (p.stolen ? 'ghost' : 'danger') + '" data-act="report" data-serial="' + esc(p.serial) + '" data-stolen="' + (p.stolen ? '0' : '1') + '">' +
                (p.stolen ? 'Found it' : 'Report') + '</button></div>';
        });
        return out + '</div>';
    }

    function alertsHtml(list) {
        var out = '<div class="notice">Get a phone notification when a card goes above or below a price. Add one from any card in the price guide.</div>';
        if (!list.length) return out + '<div class="panel">' + emptyBox('bell', 'No price alerts yet.') + '</div>';
        out += '<div class="panel list">';
        list.forEach(function (a) {
            out += '<div class="li" data-act="card" data-id="' + esc(a.cardId) + '"><div class="th">' + img({ cardId: a.cardId }) + '</div><div class="main"><div class="name">' + esc(a.name) + '</div><div class="sub">' +
                (a.dir === 'above' ? 'Goes above ' : 'Drops below ') + money(a.price) + ' · now ' + money(a.now) + '</div></div><button class="btn sm ghost" data-act="alertDel" data-id="' + a.id + '">Remove</button></div>';
        });
        return out + '</div>';
    }

    function wantsHtml(list) {
        var out = '<h2 class="sec">Wantlist <span class="muted small">' + (list || []).length + '</span></h2>';
        if (!list || !list.length) return out + '<div class="panel">' + emptyBox('heart', 'Tap “Add to wantlist” on any card and your phone pings when one is listed.') + '</div>';
        out += '<div class="panel list">';
        list.forEach(function (w) {
            out += '<div class="li" data-act="card" data-id="' + esc(w.cardId) + '"><div class="th">' + img({ cardId: w.cardId }) + '</div><div class="main"><div class="name">' + esc(w.name) + '</div><div class="sub">#' + esc(w.code) + ' · ' + money(w.price) +
                (w.live ? ' · <span class="up">' + w.live + ' live</span>' : '') + '</div></div><button class="btn sm ghost" data-act="want" data-id="' + esc(w.cardId) + '">Remove</button></div>';
        });
        return out + '</div>';
    }

    /* ----- SELLER ----- */
    V.seller = {
        title: 'Seller', tab: 'auctions',
        load: function (p) { return call('seller', { id: p.id }).then(function (r) { setNow(r.now); return r; }); },
        html: function (d) {
            var out = '<div class="pad"><div class="hero"><div class="k">Seller</div><div class="v">' + esc(d.name) + '</div><div class="s">' + ratingHtml(d.rating) + '</div>' +
                '<div class="stats"><div><b class="num">' + d.pos + '</b><span>Positive</span></div><div><b class="num">' + d.neu + '</b><span>Neutral</span></div><div><b class="num">' + d.neg + '</b><span>Negative</span></div><div><b class="num">' + d.sold + '</b><span>Sold</span></div></div></div>';
            out += '<h2 class="sec">Selling now</h2>';
            out += d.live.length ? '<div class="panel list">' + d.live.map(auctionRow).join('') + '</div>' : '<div class="panel">' + emptyBox('gavel', 'Nothing listed right now.') + '</div>';
            out += '<h2 class="sec">Feedback</h2>';
            if (!d.feedback.length) out += '<div class="panel">' + emptyBox('star', 'No ratings yet.') + '</div>';
            else {
                out += '<div class="panel list">';
                d.feedback.forEach(function (f) {
                    var tag = f.score > 0 ? '<span class="tag green">Positive</span>' : f.score < 0 ? '<span class="tag red">Negative</span>' : '<span class="tag">Neutral</span>';
                    out += '<div class="li" style="cursor:default;align-items:flex-start"><div class="main"><div class="name" style="white-space:normal">' + (f.comment ? '“' + esc(f.comment) + '”' : '<span class="muted">No comment</span>') + '</div><div class="sub">' +
                        tag + ' ' + esc(f.buyer) + ' · ' + esc(f.title || '') + (f.price ? ' · ' + money(f.price) : '') + ' · ' + ago(f.at) + '</div></div></div>';
                });
                out += '</div>';
            }
            return out + '</div>';
        },
    };

    /* ----- THIS WEEK ----- */
    V.week = {
        title: 'This week', tab: SITE ? 'week' : 'market',
        load: function () { return call('weekly').then(function (r) { setNow(r.now); return r; }); },
        html: function (w) {
            var out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">This week</h1>';
            var c = w.cardOfWeek;
            out += '<div class="hero"><div class="k">Card of the week</div>' + (c ? '<div class="v">' + esc(c.title) + '</div><div class="s">Sold for ' + money(c.price) + ' · ' + ago(c.at) + '</div>' : '<div class="v">No sales yet</div><div class="s">The biggest auction sale of the week shows here.</div>') +
                '<div class="stats"><div><b class="num">' + w.salesCount + '</b><span>Sales</span></div><div><b class="num">' + money(w.salesTotal) + '</b><span>Spent at auction</span></div><div><b class="num">' + w.bigPulls + '</b><span>Big pulls</span></div></div></div>';
            out += '<h2 class="sec">Biggest sales</h2>';
            out += w.sales.length ? '<div class="panel list">' + w.sales.map(function (s, i) {
                var t = s.cardId ? { cardId: s.cardId, graded: s.item === 'ascard_slab' } : { item: s.kind === 'lot' ? 'ascard_binder' : s.item };
                return '<div class="li"' + (s.cardId ? ' data-act="card" data-id="' + esc(s.cardId) + '"' : ' style="cursor:default"') + '><span class="rank">' + (i + 1) + '</span><div class="th' + (s.cardId ? '' : ' sealed') + '">' + img(t) + '</div><div class="main"><div class="name">' + esc(s.title) +
                    '</div><div class="sub">' + ago(s.at) + '</div></div><div class="right"><div class="price num">' + money(s.price) + '</div></div></div>';
            }).join('') + '</div>' : '<div class="panel">' + emptyBox('tag', 'No auction sales this week yet.') + '</div>';
            out += '<h2 class="sec">Biggest pulls</h2>';
            out += w.pulls.length ? '<div class="panel list">' + w.pulls.map(function (p, i) {
                return '<div class="li" data-act="card" data-id="' + esc(p.cardId) + '"><span class="rank">' + (i + 1) + '</span><div class="th">' + img({ cardId: p.cardId }) + '</div><div class="main"><div class="name">' + esc(p.title) +
                    '</div><div class="sub">Pulled by ' + esc(p.by) + ' · ' + ago(p.at) + '</div></div><div class="right"><div class="price num">' + money(p.value) + '</div></div></div>';
            }).join('') + '</div>' : '<div class="panel">' + emptyBox('fire', 'No big pulls this week yet.') + '</div>';
            var m = w.movers.up.slice(0, 5).concat(w.movers.down.slice(0, 5));
            if (m.length) {
                out += '<h2 class="sec">Price movers</h2><div class="panel list">' + m.map(function (c) {
                    return '<div class="li" data-act="card" data-id="' + esc(c.id) + '"><div class="th">' + img({ cardId: c.id }) + '</div><div class="main"><div class="name">' + esc(c.name) + '</div><div class="sub">' + esc(c.typeLabel) + ' · ' + esc(c.club) + '</div></div>' +
                        '<div class="right"><div class="price num">' + money(c.price) + '</div><div class="chg">' + pct(c.change) + '</div></div></div>';
                }).join('') + '</div>';
            }
            return out + '</div>';
        },
    };

    /* ----- RELEASE DAYS ----- */
    V.drops = {
        title: 'Release days', tab: SITE ? 'drops' : 'market', poll: true,
        load: function () { return Promise.all([S.home ? Promise.resolve(S.home) : call('home'), call('drops')]).then(function (r) { S.home = r[0]; setNow(r[1].now); return r[1]; }); },
        html: function (d) {
            var out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Release days</h1>';
            out += '<div class="notice">New products go on sale here at a set time. Only a set number exist and there’s a limit per person. What you buy is sent to ' + esc(lockerLabel()) + '.</div>';
            if (!d.list.length) return out + '<div class="panel">' + emptyBox('cal', 'No releases announced yet.') + '</div></div>';
            d.list.forEach(function (r) {
                var sold = r.quantity - r.left, pctv = r.quantity ? Math.round(sold / r.quantity * 100) : 0;
                var badge = { live: '<span class="tag green">On sale now</span>', upcoming: '<span class="tag gold">Coming soon</span>', soldout: '<span class="tag red">Sold out</span>', ended: '<span class="tag">Ended</span>' }[r.state];
                out += '<div class="panel list drop" style="margin-bottom:12px"><div class="li" style="cursor:default;border-bottom:0"><div class="th sealed">' + img({ item: r.item }) + '</div><div class="main"><div class="name" style="white-space:normal">' + esc(r.label) + '</div><div class="sub">' + badge + ' ' + money(r.price) + ' each</div></div></div>' +
                    '<div style="padding:0 14px 14px">' + (r.description ? '<div class="small muted" style="margin-bottom:10px">' + esc(r.description) + '</div>' : '') +
                    '<div class="bar"><i style="width:' + pctv + '%"></i></div><div class="small muted" style="display:flex;justify-content:space-between;margin:6px 0 10px"><span>' + r.left + ' of ' + r.quantity + ' left</span><span>' + (r.perPlayer ? 'Limit ' + r.perPlayer + ' each · you have ' + r.mine : '') + '</span></div>';
                if (r.state === 'upcoming') out += '<div class="countdown">On sale in ' + timer(r.startsAt) + '</div>';
                else if (r.state === 'live') {
                    var canBuy = !r.perPlayer || r.mine < r.perPlayer;
                    var maxQ = Math.min(r.left, r.perPlayer ? r.perPlayer - r.mine : r.left, 10);
                    if (canBuy && maxQ > 0) {
                        var opts = ''; for (var q = 1; q <= maxQ; q++) opts += '<option value="' + q + '">' + q + '</option>';
                        out += '<div class="line" style="display:flex;gap:8px"><select class="select" id="dq-' + esc(r.id) + '" style="height:46px;padding-left:14px">' + opts + '</select><button class="btn" style="flex:1" data-act="dropBuy" data-id="' + esc(r.id) + '">Buy now</button></div>';
                    } else out += '<div class="notice good">You’ve bought your limit.</div>';
                    if (r.endsAt) out += '<div class="small muted" style="margin-top:8px">Sale ends in ' + timer(r.endsAt) + '</div>';
                }
                out += '</div></div>';
            });
            return out + '</div>';
        },
    };

    /* ----- CHECK SERIAL / SEAL ----- */
    var EV_ICON = { pulled: 'box', graded: 'star', submitted: 'clock', cracked: 'x', auction: 'gavel', stolen: 'x', found: 'check', appraised: 'shield', shop: 'tag', admin: 'shield' };
    var EV_TITLE = { pulled: 'Pulled', graded: 'Graded', submitted: 'Sent for grading', cracked: 'Slab cracked', auction: 'Sold at auction', stolen: 'Reported stolen', found: 'Recovered', appraised: 'Appraised', shop: 'Sold to the shop', admin: 'Staff' };
    function fullDate(t) {
        var d = new Date(t * 1000);
        return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    }
    V.check = {
        title: 'Check a card or box', tab: 'check',
        load: function () { return Promise.resolve({}); },
        html: function () {
            var seal = S.checkMode === 'seal';
            var r = seal ? S.sealResult : S.checkResult, out = '<div class="pad">';
            if (!SITE) out += '<h1 class="ttl">Check</h1>';
            out += '<div class="seg"><button class="' + (seal ? '' : 'on') + '" data-act="checkMode" data-v="serial">Card serial</button><button class="' + (seal ? 'on' : '') + '" data-act="checkMode" data-v="seal">Box seal</button></div>';
            if (!seal) {
                out += '<div class="notice">Buying a card from someone? Type in the serial number printed on it to see if it has been reported stolen, and its history.</div>';
                out += '<div class="panel" style="padding:14px"><label class="field"><span>Serial number</span><input class="input num" id="serial" placeholder="e.g. S1-HIGHLAND-0042" value="' + esc(r ? r.serial : '') + '" autocomplete="off" style="text-transform:uppercase"></label>' +
                    '<button class="btn block" data-act="checkSerial">' + ic('shield') + ' Check</button></div>';
            } else {
                out += '<div class="notice">Buying a sealed box second-hand? Type in the seal number on the wrap. A resealed box looks the same, but its seal won’t be on record.</div>';
                out += '<div class="panel" style="padding:14px"><label class="field"><span>Seal number</span><input class="input num" id="serial" placeholder="e.g. FS-7KQ2M9XA" value="' + esc(r ? r.seal : '') + '" autocomplete="off" style="text-transform:uppercase"></label>' +
                    '<button class="btn block" data-act="checkSerial">' + ic('shield') + ' Check seal</button></div>';
            }
            if (r && seal) {
                var scls = !r.found ? 'bad' : (r.status === 'sealed' ? 'ok' : 'bad');
                out += '<div class="panel verdict ' + scls + '" style="margin-top:12px"><div class="big">' + ic(scls === 'ok' ? 'check' : 'x') + '</div>';
                if (!r.found) out += '<h3>Not a factory seal</h3><div class="muted small">No box was ever sealed with this number. It has probably been opened and shrink-wrapped again. Don’t pay sealed prices for it.</div>';
                else if (r.status === 'sealed') out += '<h3>Factory sealed</h3><div class="muted small">' + esc(r.label) + ' · sealed ' + fullDate(r.sealedAt) + '. This seal has never been opened.</div>';
                else if (r.status === 'shop') out += '<h3>Seal already used</h3><div class="muted small">A ' + esc(r.label) + ' with this seal was sold back to the card shop' + (r.openedAt ? ' on ' + fullDate(r.openedAt) : '') + '. This box is not the original.</div>';
                else out += '<h3>Seal already opened</h3><div class="muted small">The ' + esc(r.label) + ' with this seal was opened' + (r.openedAt ? ' on ' + fullDate(r.openedAt) : '') + '. This box has been resealed.</div>';
                out += '</div>';
            }
            if (r && !seal) {
                var cls = !r.known ? 'unk' : (r.stolen ? 'bad' : 'ok');
                out += '<div class="panel verdict ' + cls + '" style="margin-top:12px"><div class="big">' + ic(!r.known ? 'q' : (r.stolen ? 'x' : 'check')) + '</div>';
                if (!r.known) out += '<h3>Not on record</h3><div class="muted small">No card with that serial has been pulled. Check you typed it right. A card with no record may be fake.</div>';
                else if (r.stolen) out += '<h3>Reported stolen</h3><div class="muted small">The person who pulled this card reported it stolen' + (r.reportedAt ? '' : '') + '. Shops, graders and the auction house won’t take it.</div>';
                else out += '<h3>Not reported stolen</h3><div class="muted small">This is a real card and nobody has reported it stolen.</div>';
                if (r.card) {
                    out += '<div class="panel list" style="margin-top:14px;box-shadow:none;background:var(--card2)"><div class="li" data-act="card" data-id="' + esc(r.card.id) + '"><div class="th">' + img({ cardId: r.card.id }) +
                        '</div><div class="main" style="text-align:left"><div class="name">' + esc(r.card.name) + '</div><div class="sub">#' + esc(r.card.code) + ' · ' + esc(r.card.typeLabel) + ' · ' + esc(r.card.set || '') + '</div></div></div></div>';
                }
                out += '</div>';
                if (r.events && r.events.length) {
                    out += '<h2 class="sec">History</h2><div class="panel timeline">';
                    r.events.forEach(function (e) {
                        var bad = e.kind === 'stolen' || e.kind === 'cracked';
                        out += '<div class="tl' + (bad ? ' bad' : '') + '"><span class="dot">' + ic(EV_ICON[e.kind] || 'clock') + '</span><div class="main"><div class="name">' + esc(EV_TITLE[e.kind] || e.kind) +
                            '<span class="muted small num"> · ' + (e.at ? fullDate(e.at) : '') + '</span></div><div class="sub">' + esc(e.detail || '') + '</div></div></div>';
                    });
                    out += '</div>';
                }
            }
            return out + '</div>';
        },
    };

    // ------------------------------------------------------------------ navigation + rendering
    var SITETABS = [['market', 'Prices'], ['auctions', 'Auctions'], ['sell', 'Sell'], ['collection', 'Collection'], ['week', 'This week'], ['drops', 'Drops'], ['check', 'Check'], ['odds', 'Odds']];
    var TABS = [['market', 'Prices', 'chart'], ['auctions', 'Auctions', 'gavel'], ['sell', 'Sell', 'tag'], ['collection', 'Collection', 'grid'], ['check', 'Check', 'shield']];
    var ROUTES = { market: '/prices', auctions: '/auctions', sell: '/sell', collection: '/checklist', check: '/check', mine: '/my-auctions', odds: '/odds', week: '/week', drops: '/drops' };

    function scroller() { return SITE ? document.scrollingElement : root.querySelector('.scroll'); }

    function open(name, params, push, silent) {
        if (push && S.view) S.stack.push({ name: S.view.name, params: S.view.params, scroll: (scroller() || {}).scrollTop || 0 });
        var v = V[name];
        S.tab = v.tab;
        var keep = silent ? ((scroller() || {}).scrollTop || 0) : 0;
        S.view = { name: name, params: params || {}, data: silent && S.view && S.view.name === name ? S.view.data : null };
        if (!silent) render();
        var token = S.token = (S.token || 0) + 1;
        return v.load(params || {}).then(function (data) {
            if (token !== S.token) return;
            S.view.data = data;
            render();
            var sc = scroller();
            if (sc) sc.scrollTop = silent ? keep : (params && params._scroll) || 0;
        }, function (e) {
            if (token !== S.token) return;
            if (silent) return;
            S.view.error = e.message || String(e);
            render();
        });
    }

    function back() {
        var p = S.stack.pop();
        if (!p) return;
        var params = Object.assign({}, p.params, { _scroll: p.scroll });
        open(p.name, params, false);
    }

    function tab(name) {
        S.stack = [];
        S.checkResult = name === 'check' ? S.checkResult : S.checkResult;
        if (name === 'auctions') S.q.auctions.page = S.q.auctions.page || 1;
        open(name, {}, false);
        if (SITE && window.Site && ROUTES[name]) routeSilently(ROUTES[name]);
    }

    var routing = false;
    function routeSilently(path) { if (Site.route() !== path) { routing = true; Site.go(path); routing = false; } }

    function render() {
        var v = S.view ? V[S.view.name] : null;
        var hasBack = S.stack.length > 0;
        var html = '';
        if (!SITE) html += '<div class="safe"></div>';
        html += '<div class="topbar">' + (hasBack ? '<button class="back" data-act="back">' + ic('back') + ' Back</button><div style="flex:1"></div>' :
            '<div class="brand"><div class="mark">' + LOGO + '</div><b>LS Card <span>Exchange</span></b></div>') + '</div>';
        if (SITE && !hasBack) {
            html += '<div class="sitenav">' + SITETABS.map(function (t) { return '<button class="' + (S.tab === t[0] ? 'on' : '') + '" data-act="tab" data-v="' + t[0] + '">' + t[1] + '</button>'; }).join('') + '</div>';
        }
        var body;
        if (!S.view || (!S.view.data && !S.view.error)) body = '<div class="spin"></div>';
        else if (S.view.error) body = '<div class="pad">' + emptyBox('x', S.view.error) + '<div style="text-align:center"><button class="btn ghost sm" data-act="retry">Try again</button></div></div>';
        else body = v.html(S.view.data, S.view.params);
        html += SITE ? body + '<div class="foot">LS Card Exchange · prices update every few minutes</div>' : '<div class="scroll">' + body + '</div>';
        if (!SITE) html += '<div class="tabbar">' + TABS.map(function (t) {
            return '<button class="' + (S.tab === t[0] ? 'on' : '') + '" data-act="tab" data-v="' + t[0] + '">' + ic(t[2]) + '<span>' + t[1] + '</span></button>';
        }).join('') + '</div>';
        var sc0 = scroller(), keepTop = sc0 ? sc0.scrollTop : 0, same = S._rendered === S.view;
        root.innerHTML = html;
        S._rendered = S.view;
        var sc1 = scroller();
        if (same && sc1 && !SITE) sc1.scrollTop = keepTop;
        if (SITE && window.Site && v) Site.title(v.title);
        bindInputs();
    }

    var debounce = null;
    function bindInputs() {
        var qp = document.getElementById('q-prices');
        if (qp) qp.addEventListener('input', function () {
            clearTimeout(debounce);
            var val = qp.value;
            debounce = setTimeout(function () { S.q.prices.search = val; S.q.prices.page = 1; refocus('q-prices', function () { return open('market', {}, false, true); }); }, 350);
        });
        var qa = document.getElementById('q-auctions');
        if (qa) qa.addEventListener('input', function () {
            clearTimeout(debounce);
            var val = qa.value;
            debounce = setTimeout(function () { S.q.auctions.search = val; S.q.auctions.page = 1; refocus('q-auctions', function () { return open('auctions', {}, false, true); }); }, 350);
        });
        var sp = document.getElementById('s-prices');
        if (sp) sp.addEventListener('change', function () { S.q.prices.sort = sp.value; S.q.prices.page = 1; open('market', {}, false, true); });
        var sa = document.getElementById('s-auctions');
        if (sa) sa.addEventListener('change', function () { S.q.auctions.sort = sa.value; S.q.auctions.page = 1; open('auctions', S.view.params, false, true); });
        var serial = document.getElementById('serial');
        if (serial) serial.addEventListener('keydown', function (e) { if (e.key === 'Enter') checkSerial(); });
        var bid = document.getElementById('bid-amt');
        if (bid) bid.addEventListener('keydown', function (e) { if (e.key === 'Enter') { var b = root.querySelector('[data-act="bid"]'); if (b) b.click(); } });
    }
    // keep typing focus through a re-render
    function refocus(id, fn) {
        fn().then(function () {
            var el = document.getElementById(id);
            if (el) { el.focus(); var n = el.value.length; try { el.setSelectionRange(n, n); } catch (e) { /* type=search */ } }
        });
    }

    function busyBtn(el, on) { if (el) { el.disabled = on; } }

    function checkSerial() {
        var el = document.getElementById('serial');
        var v = el ? el.value.trim() : '';
        if (!v) return;
        if (S.checkMode === 'seal') call('seal', { seal: v }).then(function (r) { S.sealResult = r; render(); }, function (e) { toast(e.message, true); });
        else call('stolen', { serial: v }).then(function (r) { S.checkResult = r; render(); }, function (e) { toast(e.message, true); });
    }

    // ------------------------------------------------------------------ sheets
    function closeSheet() { S.sheet = null; var el = document.getElementById('sheet'); if (el) el.remove(); }
    function renderSheet() {
        var sh = S.sheet;
        var old = document.getElementById('sheet');
        if (old) old.remove();
        if (!sh) return;
        var inner = '';
        if (sh.kind === 'sell') {
            var it = sh.item;
            var d = sh.durations.filter(function (x) { return x.id === sh.dur; })[0] || sh.durations[0];
            var head = '';
            if (sh.lot) {
                var total = 0; sh.lot.forEach(function (x) { total += x.value || 0; });
                head = '<h3>Auction this lot</h3><div class="panel list" style="box-shadow:none;background:var(--card2);margin-bottom:10px;max-height:190px;overflow-y:auto">' + sh.lot.map(function (x) {
                    return '<div class="li" style="cursor:default;padding:7px 12px"><div class="th' + (x.kind === 'sealed' ? ' sealed' : '') + '" style="width:34px;height:44px">' + img(x.thumb) + '</div><div class="main"><div class="name" style="font-size:14px">' + esc(x.title) + '</div></div><div class="right small num">' + money(x.value) + '</div></div>';
                }).join('') + '</div><div class="muted small" style="margin:-4px 0 10px">' + sh.lot.length + ' items · worth about ' + money(total) + ' together</div>' +
                    '<label class="field"><span>Lot name (optional)</span><input class="input" id="f-title" maxlength="60" placeholder="e.g. Arsenic starter bundle" value="' + esc(sh.title || '') + '"></label>';
                it = { value: total };
            } else {
                head = '<h3>Auction this item</h3><div class="panel list" style="box-shadow:none;background:var(--card2);margin-bottom:14px"><div class="li" style="cursor:default"><div class="th' + (it.kind === 'sealed' ? ' sealed' : '') + '">' + img(it.thumb) +
                    '</div><div class="main"><div class="name">' + esc(it.title) + '</div><div class="sub">Worth about ' + money(it.value) + '</div></div></div></div>';
            }
            inner = head +
                '<label class="field"><span>Starting price</span><div class="money-in"><input class="input num" id="f-start" type="number" inputmode="numeric" min="1" value="' + (sh.start || Math.max(1, Math.floor(it.value * 0.6))) + '"></div></label>' +
                '<div class="grid2"><label class="field"><span>Buy it now (optional)</span><div class="money-in"><input class="input num" id="f-bin" type="number" inputmode="numeric" placeholder="None" value="' + (sh.bin || '') + '"></div></label>' +
                '<label class="field"><span>Reserve (optional)</span><div class="money-in"><input class="input num" id="f-res" type="number" inputmode="numeric" placeholder="None" value="' + (sh.res || '') + '"></div></label></div>' +
                '<div class="field"><span>How long</span></div><div class="durs">' + sh.durations.map(function (x) {
                    return '<button class="dur' + (x.id === sh.dur ? ' on' : '') + '" data-act="dur" data-v="' + x.id + '"><b>' + esc(x.label) + '</b><span>' + money(x.fee) + ' fee</span></button>';
                }).join('') + '</div>' +
                '<div class="sum"><div><span class="muted">Listing fee (paid now, not refunded)</span><span class="num">' + money(d ? d.fee : 0) + '</span></div>' +
                '<div><span class="muted">Final value fee (when it sells)</span><span class="num">' + Math.round((sh.fvf || 0) * 100) + '%</span></div>' +
                '<div class="t"><span>Returned if unsold</span><span>' + esc(lockerLabel().replace('Postal Prime locker: ', '')) + '</span></div></div>' +
                '<button class="btn block" style="margin-top:14px" data-act="sellGo">List it</button><button class="btn ghost block" style="margin-top:8px" data-act="closeSheet">Cancel</button>';
        } else if (sh.kind === 'alert') {
            inner = '<h3>Price alert</h3><div class="muted small" style="margin:-6px 0 12px">' + esc(sh.name) + ' is ' + money(sh.price) + ' right now.</div>' +
                '<div class="seg"><button class="' + (sh.dir === 'above' ? 'on' : '') + '" data-act="adir" data-v="above">Goes above</button><button class="' + (sh.dir === 'below' ? 'on' : '') + '" data-act="adir" data-v="below">Drops below</button></div>' +
                '<label class="field"><span>Price</span><div class="money-in"><input class="input num" id="f-alert" type="number" inputmode="numeric" value="' + (sh.target || '') + '"></div></label>' +
                '<button class="btn block" data-act="alertGo">Save alert</button><button class="btn ghost block" style="margin-top:8px" data-act="closeSheet">Cancel</button>';
        } else if (sh.kind === 'lockers') {
            var h = S.home || {};
            inner = '<h3>Delivery locker</h3>';
            if (!h.postal) inner += '<div class="notice">Postal Prime isn’t running, so won cards go straight into your pockets the next time you’re online.</div>';
            else inner += '<div class="muted small" style="margin:-6px 0 12px">Auction wins and returned items are sent to this Postal Prime locker.</div><div class="panel list" style="box-shadow:none;background:var(--card2)">' +
                h.lockers.map(function (l) {
                    return '<div class="li" data-act="lockerPick" data-v="' + esc(l.id) + '"><div class="main"><div class="name">' + ic('pin') + ' ' + esc(l.label) + '</div></div>' + (l.id === h.locker ? '<span class="up">' + ic('check') + '</span>' : '') + '</div>';
                }).join('') + '</div>';
            inner += '<button class="btn ghost block" style="margin-top:12px" data-act="closeSheet">Done</button>';
        } else if (sh.kind === 'offer') {
            inner = '<h3>Make an offer</h3><div class="muted small" style="margin:-6px 0 12px">Buy it now is ' + money(sh.bin) + '. The seller takes offers from ' + money(sh.min) + '. Your offer is taken from your ' + esc(S.home.account) +
                ' now and comes back if the seller declines, doesn’t answer within a day, or someone bids.</div>' +
                '<label class="field"><span>Your offer</span><div class="money-in"><input class="input num" id="f-offer" type="number" inputmode="numeric" min="' + sh.min + '" max="' + (sh.bin - 1) + '" value="' + (sh.mine || Math.round((sh.min + sh.bin) / 2)) + '"></div></label>' +
                '<button class="btn block" data-act="offerGo">' + (sh.mine ? 'Change offer' : 'Send offer') + '</button><button class="btn ghost block" style="margin-top:8px" data-act="closeSheet">Cancel</button>';
        } else if (sh.kind === 'rate') {
            inner = '<h3>Rate the seller</h3><div class="seg">' + [[1, 'Positive'], [0, 'Neutral'], [-1, 'Negative']].map(function (x) {
                return '<button class="' + (sh.score === x[0] ? 'on' : '') + '" data-act="rscore" data-v="' + x[0] + '">' + x[1] + '</button>';
            }).join('') + '</div><label class="field"><span>Comment (optional)</span><input class="input" id="f-comment" maxlength="120" placeholder="e.g. Great card, fast delivery" value="' + esc(sh.comment || '') + '"></label>' +
                '<button class="btn block" data-act="rateGo">Leave rating</button><button class="btn ghost block" style="margin-top:8px" data-act="closeSheet">Cancel</button>';
        } else if (sh.kind === 'confirm') {
            inner = '<h3>' + esc(sh.title) + '</h3><div class="muted" style="margin-bottom:14px">' + esc(sh.text) + '</div><button class="btn block" data-act="confirmGo">' + esc(sh.ok) + '</button>' +
                '<button class="btn ghost block" style="margin-top:8px" data-act="closeSheet">Cancel</button>';
        }
        var bg = document.createElement('div');
        bg.id = 'sheet';
        bg.className = 'sheet-bg';
        bg.innerHTML = '<div class="sheet">' + inner + '</div>';
        bg.addEventListener('click', function (e) { if (e.target === bg) closeSheet(); });
        document.body.appendChild(bg);
    }
    function confirmSheet(title, text, ok, fn) { S.sheet = { kind: 'confirm', title: title, text: text, ok: ok, fn: fn }; renderSheet(); }
    function readSellForm() {
        var sh = S.sheet;
        sh.start = (document.getElementById('f-start') || {}).value;
        sh.bin = (document.getElementById('f-bin') || {}).value;
        sh.res = (document.getElementById('f-res') || {}).value;
        var t = document.getElementById('f-title'); if (t) sh.title = t.value;
    }

    // ------------------------------------------------------------------ actions
    function act(el, e) {
        var a = el.getAttribute('data-act');
        var v = el.getAttribute('data-v');
        var id = el.getAttribute('data-id');
        switch (a) {
            case 'tab': tab(v); break;
            case 'back': back(); break;
            case 'retry': open(S.view.name, S.view.params, false); break;
            case 'goto': S.stack = []; open(v, {}, false); if (SITE && ROUTES[v]) routeSilently(ROUTES[v]); break;
            case 'card': open('card', { id: id }, true); break;
            case 'odds': if (SITE) { tab('odds'); } else open('odds', {}, true); break;
            case 'cardAuctions': open('auctions', { cardId: id }, true); break;
            case 'auction': open('auction', { id: Number(id) }, true); break;
            case 'ptype': S.q.prices.type = v; S.q.prices.page = 1; open('market', {}, false, true); break;
            case 'ppage': S.q.prices.page = Number(v); open('market', {}, false); break;
            case 'akind': S.q.auctions.kind = v; S.q.auctions.page = 1; open('auctions', S.view.params, false, true); break;
            case 'apage': S.q.auctions.page = Number(v); open('auctions', S.view.params, false); break;
            case 'mseg': S.seg.mine = v; render(); break;
            case 'cseg': S.seg.collection = v; open('collection', {}, false); break;
            case 'clset': S.checklist.set = v; S.checklist.limit = 0; render(); break;
            case 'clf': S.checklist.filter = v; S.checklist.limit = 0; render(); break;
            case 'clt': S.checklist.type = v; S.checklist.limit = 0; render(); break;
            case 'clmore': S.checklist.limit = (S.checklist.limit || 120) + 120; render(); break;
            case 'checkSerial': checkSerial(); break;
            case 'checkMode': S.checkMode = v; render(); break;
            case 'report':
                var stolen = el.getAttribute('data-stolen') === '1', serial = el.getAttribute('data-serial');
                confirmSheet(stolen ? 'Report stolen?' : 'Mark as found?', stolen ? serial + ' will show as stolen on every serial check, and shops and the auction house will refuse it.' : serial + ' will no longer show as stolen.',
                    stolen ? 'Report stolen' : 'Mark as found', function () {
                        return call('report', { serial: serial, stolen: stolen }).then(function () { toast(stolen ? 'Reported stolen' : 'Marked as found'); open('collection', {}, false, true); });
                    });
                break;
            case 'alertNew':
                S.sheet = { kind: 'alert', cardId: id, name: el.getAttribute('data-name'), price: Number(el.getAttribute('data-price')), dir: 'above' };
                S.sheet.target = Math.ceil(S.sheet.price * 1.2);
                renderSheet(); break;
            case 'adir': S.sheet.target = (document.getElementById('f-alert') || {}).value; S.sheet.dir = v;
                if (!S.sheet.target || S.sheet.target == Math.ceil(S.sheet.price * (v === 'above' ? 0.8 : 1.2))) S.sheet.target = Math.max(1, Math.round(S.sheet.price * (v === 'above' ? 1.2 : 0.8)));
                renderSheet(); break;
            case 'alertGo':
                var sh = S.sheet;
                busyBtn(el, true);
                call('alertAdd', { cardId: sh.cardId, dir: sh.dir, price: Number((document.getElementById('f-alert') || {}).value) }).then(function () {
                    closeSheet(); toast('Price alert saved');
                }, function (err) { busyBtn(el, false); toast(err.message, true); });
                break;
            case 'alertDel':
                e.stopPropagation();
                call('alertDel', { id: Number(id) }).then(function () { open('collection', {}, false, true); }, function (err) { toast(err.message, true); });
                break;
            case 'bid':
                var amt = Number((document.getElementById('bid-amt') || {}).value);
                confirmSheet('Place a bid of ' + money(amt) + '?', 'The money is taken from your ' + S.home.account + ' now. You get it back if someone outbids you.', 'Place bid', function () {
                    return call('bid', { id: Number(id), amount: amt }).then(function (r) {
                        toast(r && r.bought ? 'You bought it!' : (r && r.extended ? 'Bid placed. The auction was extended.' : 'Bid placed')); open('auction', S.view.params, false, true);
                    });
                });
                break;
            case 'buyNow':
                confirmSheet('Buy it now for ' + money(el.getAttribute('data-price')) + '?', 'It will be sent to ' + lockerLabel() + '.', 'Buy it now', function () {
                    return call('buyNow', { id: Number(id) }).then(function () { toast('You bought it!'); open('auction', S.view.params, false, true); });
                });
                break;
            case 'cancel':
                confirmSheet('Cancel this auction?', 'The item is sent back to ' + lockerLabel() + '. The listing fee is not refunded.', 'Cancel auction', function () {
                    return call('cancel', { id: Number(id) }).then(function () { toast('Auction cancelled'); back(); });
                });
                break;
            case 'watch':
                call('watch', { id: Number(id) }).then(function (r) { toast(r.watching ? 'Added to your watch list' : 'Removed from your watch list'); open('auction', S.view.params, false, true); }, function (err) { toast(err.message, true); });
                break;
            case 'lockers': S.sheet = { kind: 'lockers' }; renderSheet(); break;
            case 'lockerPick':
                call('setLocker', { locker: v }).then(function (r) { S.home.locker = r.locker; renderSheet(); render(); toast('Delivery locker saved'); }, function (err) { toast(err.message, true); });
                break;
            case 'sellPick':
                var d = S.view.data, it = d.items[Number(el.getAttribute('data-i'))];
                if (it.stolen) { toast('This card has been reported stolen and can’t be listed.', true); break; }
                if (S.lot) {
                    if (S.lot[it.slot]) delete S.lot[it.slot];
                    else if (Object.keys(S.lot).length >= (S.home.maxLot || 10)) toast('A lot can hold up to ' + (S.home.maxLot || 10) + ' items.', true);
                    else S.lot[it.slot] = true;
                    render(); break;
                }
                sellSheet(it, d); break;
            case 'lotMode': S.lot = v === '1' ? {} : null; render(); break;
            case 'lotGo':
                var dd = S.view.data;
                var picks = dd.items.filter(function (x) { return S.lot && S.lot[x.slot]; });
                if (picks.length < 2) { toast('Pick at least 2 items.', true); break; }
                sellSheet(picks[0], dd, picks); break;
            case 'offerOpen':
                S.sheet = { kind: 'offer', id: Number(id), min: Number(el.getAttribute('data-min')), bin: Number(el.getAttribute('data-bin')), mine: Number(el.getAttribute('data-mine')) || 0 };
                renderSheet(); break;
            case 'offerGo':
                var oa = Number((document.getElementById('f-offer') || {}).value);
                busyBtn(el, true);
                call('offer', { id: S.sheet.id, amount: oa }).then(function () { closeSheet(); toast('Offer sent to the seller'); open('auction', S.view.params, false, true); },
                    function (err) { busyBtn(el, false); toast(err.message, true); });
                break;
            case 'offerAnswer':
                var acc = v === '1', oamt = el.getAttribute('data-amount');
                confirmSheet(acc ? 'Accept ' + money(oamt) + '?' : 'Decline this offer?', acc ? 'The auction ends now and the buyer gets the item. Other offers are refunded.' : 'The buyer gets their money back.', acc ? 'Accept offer' : 'Decline', function () {
                    return call('offerAnswer', { id: Number(id), accept: acc }).then(function () { toast(acc ? 'Sold!' : 'Offer declined'); open('auction', S.view.params, false, true); });
                });
                break;
            case 'rateOpen': e.stopPropagation(); S.sheet = { kind: 'rate', id: Number(id), score: 1 }; renderSheet(); break;
            case 'rscore': S.sheet.comment = (document.getElementById('f-comment') || {}).value; S.sheet.score = Number(v); renderSheet(); break;
            case 'rateGo':
                busyBtn(el, true);
                call('rate', { id: S.sheet.id, score: S.sheet.score, comment: (document.getElementById('f-comment') || {}).value || '' }).then(function () { closeSheet(); toast('Thanks for rating'); open('mine', {}, false, true); },
                    function (err) { busyBtn(el, false); toast(err.message, true); });
                break;
            case 'seller': open('seller', { id: Number(id) }, true); break;
            case 'appraiseOpen': open('appraise', {}, true); break;
            case 'letterSave':
                call('appraisalSave', { ref: id }).then(function () { toast('Saved to your phone: Files → Card Exchange'); }, function (err) { toast(err.message, true); });
                break;
            case 'letterSaveComputer':
                call('appraisalSaveComputer', { ref: id }).then(function () { toast('Saved to your computer: File Explorer → Downloads'); }, function (err) { toast(err.message, true); });
                break;
            case 'letterPrint':
                if (window.Site && Site.print) Site.print('appraisalPrint', { ref: id }, { title: 'Appraisal ' + id });
                break;
            case 'appraiseGo':
                var ad = S.view.data, ait = ad.items[Number(el.getAttribute('data-i'))];
                confirmSheet('Appraise ' + ait.title + '?', money(ad.price) + ' from your ' + S.home.account + '. The letter is sent to ' + lockerLabel() + '.', 'Order letter', function () {
                    return call('appraise', { slot: ait.slot, serial: ait.serial }).then(function (r) { toast('Letter ordered: valued at ' + money(r.value)); open('appraise', {}, false, true); });
                });
                break;
            case 'want':
                call('want', { cardId: id }).then(function (r) { toast(r.wanted ? 'Added to your wantlist' : 'Removed from your wantlist'); if (S.view.name === 'card') open('card', S.view.params, false, true); else open(S.view.name, S.view.params, false, true); },
                    function (err) { toast(err.message, true); });
                if (e) e.stopPropagation();
                break;
            case 'week': if (SITE) tab('week'); else open('week', {}, true); break;
            case 'drops': if (SITE) tab('drops'); else open('drops', {}, true); break;
            case 'dropBuy':
                var drop = (S.view.data.list || []).filter(function (x) { return x.id === id; })[0];
                if (!drop) break;
                var q = Number((document.getElementById('dq-' + id) || {}).value || 1);
                confirmSheet('Buy ' + q + ' × ' + drop.label + '?', money(drop.price * q) + ' from your ' + S.home.account + '. It’s sent to ' + lockerLabel() + '.', 'Buy', function () {
                    return call('dropBuy', { id: id, qty: q }).then(function (r) { toast('Bought! It’s on its way to your locker.'); open('drops', S.view.params, false, true); });
                });
                break;
            case 'dur': readSellForm(); S.sheet.dur = v; renderSheet(); break;
            case 'sellGo':
                readSellForm();
                var s = S.sheet, item = s.item;
                busyBtn(el, true);
                var args = { duration: s.dur, start: Number(s.start), buyNow: s.bin ? Number(s.bin) : null, reserve: s.res ? Number(s.res) : null };
                if (s.lot) { args.slots = s.lot.map(function (x) { return { slot: x.slot, serial: x.serial }; }); args.title = s.title || ''; }
                else { args.slot = item.slot; args.serial = item.serial; }
                call('list', args).then(function (r) {
                    closeSheet(); toast('Your auction is live'); S.lot = null;
                    S.stack = []; open('auction', { id: r.id }, false); S.stack = [{ name: 'mine', params: {} }]; S.tab = 'auctions';
                }, function (err) { busyBtn(el, false); toast(err.message, true); });
                break;
            case 'confirmGo':
                var fn = S.sheet && S.sheet.fn;
                busyBtn(el, true);
                Promise.resolve(fn && fn()).then(function () { closeSheet(); }, function (err) { busyBtn(el, false); toast(err.message, true); });
                break;
            case 'closeSheet': closeSheet(); break;
        }
    }

    document.addEventListener('click', function (e) {
        var el = e.target.closest ? e.target.closest('[data-act]') : null;
        if (!el || el.disabled) return;
        act(el, e);
    });

    // live countdowns
    setInterval(function () {
        var els = document.querySelectorAll('[data-ends]');
        for (var i = 0; i < els.length; i++) {
            var t = Number(els[i].getAttribute('data-ends'));
            els[i].textContent = left(t);
            if (t - now() < 300) els[i].classList.add('soon');
        }
    }, 1000);

    // refresh auction screens while they're open
    setInterval(function () {
        if (document.visibilityState !== 'visible' || S.sheet || !S.view || !S.view.data) return;
        var v = V[S.view.name];
        if (!v.poll) return;
        var ae = document.activeElement;
        if (ae && (ae.tagName === 'INPUT' || ae.tagName === 'SELECT')) return;
        open(S.view.name, S.view.params, false, true);
    }, 10000);

    // ------------------------------------------------------------------ start
    ASC.start = function (path) {
        var map = { '/prices': 'market', '/auctions': 'auctions', '/sell': 'sell', '/checklist': 'collection', '/check': 'check', '/my-auctions': 'mine', '/odds': 'odds', '/week': 'week', '/drops': 'drops' };
        var name = map[path] || 'market';
        S.stack = [];
        open(name, {}, false);
    };
    ASC.route = function (path) {
        if (routing) return;
        var map = { '/prices': 'market', '/': 'market', '/auctions': 'auctions', '/sell': 'sell', '/checklist': 'collection', '/check': 'check', '/my-auctions': 'mine', '/odds': 'odds', '/week': 'week', '/drops': 'drops' };
        if (map[path] && (!S.view || S.view.name !== map[path] || S.stack.length)) { S.stack = []; open(map[path], {}, false); }
    };
    ASC.refresh = function () { if (S.view) open(S.view.name, S.view.params, false, true); };
})();
