/* as-tradingcards v3 screens: deck box, battle table, leaderboard, skins, trader, card shop.
   Uses the card renderer from app.js (window.ascardHost). Vanilla JS, no innerHTML from data. */
(() => {
    'use strict';
    const host = window.ascardHost;
    if (!host) return;
    const { h, post, sfx, renderCard, root } = host;
    const handlers = {};
    window.ascardV2 = { handlers };

    const money = n => '£' + Math.floor(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const S = () => host.sfxCfg();
    const pct = (a, b) => b > 0 ? Math.max(0, Math.min(100, Math.round(a / b * 100))) : 0;
    const dur = s => { s = Math.max(0, Math.floor(s)); const d = Math.floor(s / 86400), hh = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60); return d ? `${d}d ${hh}h` : hh ? `${hh}h ${m}m` : `${m}m`; };
    const mmss = s => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
    const TYPE_COL = { player: '#e9e9ec', star: '#d6453d', captain: '#3f7bd6', winner: '#3aa56b', century: '#d8a31f', legend: '#f6d57a' };

    function mini(display, w) {
        // w = pixel width of the card (base card is 300 wide)
        return renderCard(display, { scale: w / 300, tilt: false, flipped: true });
    }
    function back(w) {
        return renderCard({ rarity: {} }, { scale: w / 300, tilt: false, flipped: false });
    }

    function screen(cls, mode, top, body, side) {
        host.clear();
        host.setMode(mode || 'v2');
        const el = h('div', { class: 'v2 ' + (cls || '') }, top, h('div', { class: 'v2-main' }, body, side || null));
        root.appendChild(el);
        return el;
    }
    function topBar(title, sub, right) {
        return h('div', { class: 'v2-top' },
            h('div', { class: 'v2-row', style: { 'align-items': 'baseline', gap: '14px' } }, h('h1', null, title), sub ? h('span', { class: 'v2-sub' }, sub) : null),
            h('div', { class: 'v2-row' }, right || null, h('button', { class: 'v2-btn small', onclick: () => host.close() }, 'Close')));
    }
    function toast(el, msg, kind) {
        const t = h('div', { class: 'v2-toast ' + (kind || '') }, msg);
        el.appendChild(t);
        setTimeout(() => t.remove(), 3200);
    }
    const alive = el => el && el.isConnected;

    /* ================================================================ DECK BOX */
    let dk = null;
    function deckOpen(d) { dk = { data: d, type: 'all', q: '', busy: false }; deckRender(); }
    handlers.deckOpen = deckOpen;

    async function deckAct(name, payload, okMsg) {
        if (dk.busy) return;
        dk.busy = true;
        const r = await post(name, payload);
        dk.busy = false;
        if (r && r.ok) { dk.data = r.data; deckRender(); if (r.data.note) toast(root.firstChild, r.data.note, 'err'); else if (okMsg) toast(root.firstChild, okMsg, 'ok'); }
        else toast(root.firstChild, (r && r.error) || 'Could not do that.', 'err');
    }

    function deckRender() {
        if (!dk) return;
        const d = dk.data;
        const typeLabel = {};
        d.pocket.concat(d.cards).forEach(c => { typeLabel[c.display.rarity.id] = c.display.rarity.label; });
        const q = dk.q.trim().toLowerCase();
        const pocket = d.pocket.filter(c => (dk.type === 'all' || c.display.rarity.id === dk.type) && (!q || (c.display.label || '').toLowerCase().includes(q) || (c.display.club.label || '').toLowerCase().includes(q)));
        const copies = d.copies || {};
        const full = d.cards.length >= d.size;

        const chips = h('div', { class: 'v2-chips' },
            ['all'].concat(Object.keys(typeLabel)).map(t => h('button', { class: 'v2-chip' + (dk.type === t ? ' on' : ''), onclick: () => { dk.type = t; deckRender(); } }, t === 'all' ? 'All' : typeLabel[t])));
        const search = h('input', { class: 'v2-input', type: 'text', placeholder: 'Search name or club', value: dk.q, style: { width: '220px' } });
        search.addEventListener('input', () => { dk.q = search.value; const pos = search.selectionStart; deckRender(); const n = root.querySelector('.v2 input[type=text]'); if (n) { n.focus(); n.setSelectionRange(pos, pos); } });
        search.addEventListener('keyup', e => e.stopPropagation());

        const grid = h('div', { class: 'dk-pocket' }, pocket.map(c => {
            const n = copies[c.cardId] || 0;
            const blocked = full || n >= d.rules.copies || (c.display.rarity.id === 'legend' && d.legends >= d.rules.legend);
            return h('div', { class: 'dk-cell' + (blocked ? ' in' : ''), title: blocked ? 'Can’t add (full, too many copies or a second legend)' : 'Click to add', onclick: () => deckAct('deckAdd', { slot: c.slot, serial: c.serial }) },
                mini(c.display, 112),
                h('span', { class: 'v2-tag mute' }, n ? `${n} in box` : 'Add'));
        }));

        // side
        const atts = d.cards.map(c => c.display.att || 0), defs = d.cards.map(c => c.display.def || 0);
        const avg = a => a.length ? Math.round(a.reduce((x, y) => x + y, 0) / a.length) : 0;
        const mix = {};
        d.cards.forEach(c => { const id = c.display.rarity.id; mix[id] = (mix[id] || 0) + 1; });
        const groups = {};
        d.cards.forEach(c => { (groups[c.cardId] = groups[c.cardId] || []).push(c); });
        const nameIn = h('input', { class: 'v2-input v2-grow', type: 'text', value: d.name === 'Deck box' ? '' : d.name, placeholder: 'Deck box name', maxlength: '32' });
        nameIn.addEventListener('keyup', e => { e.stopPropagation(); if (e.key === 'Enter') deckAct('deckRename', { name: nameIn.value }, 'Renamed.'); });
        nameIn.addEventListener('blur', () => { if ((nameIn.value || 'Deck box') !== d.name) deckAct('deckRename', { name: nameIn.value }); });

        const side = h('div', { class: 'v2-side', style: { width: '420px' } },
            h('div', { class: 'v2-row' },
                h('div', { style: { width: '72px', height: '92px', 'border-radius': '8px', background: 'linear-gradient(160deg,#27324f,#141b2e)', border: '1.5px solid var(--v2-accent)', display: 'grid', 'place-items': 'center', flex: 'none' } }, h('div', { style: { width: '26px', height: '26px', 'border-radius': '50%', border: '2px solid var(--v2-accent)' } })),
                h('div', { class: 'v2-grow', style: { display: 'flex', 'flex-direction': 'column', gap: '6px' } }, h('span', { class: 'v2-label' }, 'Deck box name'), nameIn)),
            h('div', null,
                h('div', { class: 'v2-row v2-spread', style: { 'align-items': 'baseline' } }, h('span', { class: 'v2-label' }, 'Cards in deck'), h('span', { class: 'v2-big', style: { 'font-size': '26px' } }, `${d.cards.length} `, h('span', { style: { color: 'var(--v2-muted)', 'font-size': '18px' } }, `/ ${d.size}`))),
                h('div', { class: 'v2-bar', style: { 'margin-top': '6px' } }, h('i', { style: { width: pct(d.cards.length, d.size) + '%' } })),
                h('div', { class: 'v2-note', style: { 'margin-top': '6px' } }, d.valid ? 'Ready to battle.' : (d.cards.length < d.size ? `${d.size - d.cards.length} more card${d.size - d.cards.length === 1 ? '' : 's'} to fill the box.` : d.why))),
            h('div', { style: { display: 'grid', 'grid-template-columns': '1fr 1fr', gap: '10px' } },
                h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Average attack'), h('div', { class: 'v2-big v2-att' }, String(avg(atts)))),
                h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Average defence'), h('div', { class: 'v2-big v2-def' }, String(avg(defs))))),
            h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '8px' } },
                h('div', { class: 'v2-label' }, 'Rarity mix'),
                Object.keys(typeLabel).map(id => h('div', { class: 'dk-mix' }, h('span', { style: { width: '78px', color: '#c5cbd9' } }, typeLabel[id]),
                    h('div', { class: 'v2-bar v2-grow' }, h('i', { style: { width: pct(mix[id] || 0, Math.max(d.cards.length, 1)) + '%', background: TYPE_COL[id] || '#888' } })), h('span', { class: 'n' }, String(mix[id] || 0))))),
            h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '6px' } },
                h('div', { class: 'v2-label' }, `In this deck · max ${d.rules.copies} of a card, ${d.rules.legend} legend`),
                Object.keys(groups).length === 0 ? h('div', { class: 'v2-note' }, 'Click cards in your pockets to put them in the box.') : null,
                Object.values(groups).map(g => h('div', { class: 'v2-listrow', style: { cursor: 'pointer' }, title: 'Click to take one out', onclick: () => deckAct('deckRemove', { serial: g[g.length - 1].serial }) },
                    h('span', { class: 'v2-dot', style: { background: TYPE_COL[g[0].display.rarity.id] || '#888' } }),
                    h('span', { class: 'v2-grow', style: { 'font-weight': 600 } }, g[0].display.label),
                    h('span', { class: 'v2-att' }, String(g[0].display.att)), h('span', { class: 'v2-def' }, String(g[0].display.def)),
                    h('span', { style: { width: '26px', 'text-align': 'right', color: 'var(--v2-muted)' } }, 'x' + g.length)))),
            h('div', { class: 'v2-row' },
                h('button', { class: 'v2-btn primary v2-grow', onclick: () => host.close() }, 'Done'),
                h('button', { class: 'v2-btn', onclick: () => deckAct('deckClear', {}, 'Cards returned to your pockets.') }, 'Take all out')));

        const el = screen('dk', 'v2',
            topBar('Deck box', `Exactly ${d.size} raw cards · max ${d.rules.copies} copies · ${d.rules.legend} legend`, h('span', { class: 'v2-pill' + (d.valid ? '' : ' warn') }, d.valid ? 'Valid deck' : `${d.cards.length} / ${d.size}`)),
            h('div', { class: 'v2-body' },
                h('div', { class: 'v2-row v2-spread' }, h('h1', { style: { 'font-size': '26px' } }, 'Your pockets'), search),
                chips,
                pocket.length ? grid : h('div', { class: 'v2-note' }, d.pocket.length ? 'No cards match.' : 'You have no raw cards on you. Slabs can’t go in a deck box.')),
            side);
    }

    /* ================================================================ SKINS */
    let sk = null;
    handlers.skins = d => { sk = { data: d }; skinsRender(); };
    function skinsRender(msg) {
        const d = sk.data;
        const covers = h('div', { class: 'v2-row', style: { 'align-items': 'flex-start', gap: '24px', 'flex-wrap': 'wrap' } }, d.covers.map(c =>
            h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '10px', 'align-items': 'center' } },
                h('div', { class: 'v2-binder', style: { background: c.cover, 'border-color': c.edge } }, h('div', { class: 'ring', style: { 'border-color': c.ring } }), h('div', { class: 'ttl', style: { color: c.title } }, c.label), h('div', { class: 'spine', style: { background: c.spine } })),
                h('div', { style: { 'font-weight': 600 } }, c.label),
                c.owned ? h('div', { class: 'v2-tag' }, 'Owned') :
                    d.nearShop ? h('button', { class: 'v2-btn small primary', onclick: async () => { const r = await post('buyCover', { id: c.id }); if (r && r.ok) { c.owned = true; skinsRender('Cover unlocked.'); } else toast(root.firstChild, (r && r.error) || 'Could not buy it.', 'err'); } }, `Buy · ${money(c.price)}`)
                        : h('div', { class: 'v2-tag mute' }, `Shop · ${money(c.price)}`))));
        const mats = h('div', { style: { display: 'grid', 'grid-template-columns': 'repeat(auto-fill,minmax(260px,1fr))', gap: '18px' } }, d.mats.map(m => {
            const sel = d.myMat === m.id;
            const style = { background: m.bg, 'border-color': sel ? 'var(--v2-accent)' : 'rgba(255,255,255,.16)', 'border-width': sel ? '2.5px' : '1px', cursor: 'pointer' };
            if (m.image) style['background-image'] = `url(${m.image})`;
            return h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '8px' } },
                h('div', { class: 'v2-mat', style, onclick: async () => { const r = await post('setMat', { id: m.id }); if (r && r.ok) { d.myMat = m.id; skinsRender('Playmat saved.'); } } },
                    h('div', { class: 'mid', style: { background: m.line } }),
                    h('div', { class: 'slots' }, [0, 1, 2, 3, 4].map(() => h('i', { style: { 'border-color': m.slot } })))),
                h('div', { class: 'v2-row v2-spread' }, h('span', { style: { 'font-weight': 600 } }, m.label), h('span', { class: sel ? 'v2-tag' : 'v2-tag mute' }, sel ? 'Selected' : (m.custom ? 'From the board creator' : 'Free'))));
        }));
        const slabs = h('div', { class: 'v2-row', style: { gap: '22px', 'flex-wrap': 'wrap', 'align-items': 'flex-start' } }, (d.slabs || []).map(s =>
            h('div', { style: { display: 'flex', 'flex-direction': 'column', gap: '8px', 'align-items': 'center' } },
                h('div', { class: 'v2-slab' }, h('div', { class: 'lbl', style: { background: s.bg, color: s.fg } }, h('div', null, h('b', null, s.label.toUpperCase()), h('span', null, 'SAMPLE · #001')), h('em', null, s.id === 'standard' ? '9' : '10')),
                    h('div', { style: { width: '112px', height: '157px', 'border-radius': '6px', background: 'linear-gradient(160deg,#27324f,#141b2e)', border: '1px solid rgba(255,255,255,.2)' } })),
                h('div', { style: { 'font-weight': 600 } }, s.label), h('div', { class: 'v2-tag mute' }, s.use))));
        const el = screen('', 'v2', topBar('Covers, mats and labels', 'Your style'),
            h('div', { class: 'v2-body' },
                h('h1', { style: { 'font-size': '26px' } }, 'Binder covers'), h('div', { class: 'v2-note' }, 'Pick a cover on the binder screen with the COVER button. Covers are bought at the card shop counter.'), covers,
                h('div', { style: { height: '1px', background: 'var(--v2-line)', margin: '10px 0' } }),
                h('h1', { style: { 'font-size': '26px' } }, 'Playmats'), h('div', { class: 'v2-note' }, 'Your mat shows on your side of the table. Mats from the board creator appear here automatically.'), mats,
                h('div', { style: { height: '1px', background: 'var(--v2-line)', margin: '10px 0' } }),
                h('h1', { style: { 'font-size': '26px' } }, 'Slab label skins'), h('div', { class: 'v2-note' }, 'Chosen automatically when a card is graded.'), slabs));
        if (msg) toast(el, msg, 'ok');
    }

    /* ================================================================ LEADERBOARD */
    handlers.btBoard = d => {
        const me = d.me;
        const tierRows = (d.tiers || []).map(t => h('div', { class: 'lb-tier' + (me.tier.id === t.id ? ' here' : '') }, h('b', null, t.label), h('span', { class: 'v2-note' }, `${t.min}+ points`)));
        const rows = (d.top || []).map(r => h('tr', { class: r.name === me.name ? 'lb-me' : '' }, h('td', null, String(r.pos)), h('td', { style: { 'font-weight': 600 } }, r.name), h('td', null, r.tier), h('td', { class: 'num' }, `${r.wins}-${r.losses}`), h('td', { class: 'num', style: { 'font-weight': 700, color: 'var(--v2-accent)' } }, String(r.points))));
        const t = d.tourney;
        const tourney = t ? h('div', { class: 'v2-card', style: { display: 'flex', 'flex-direction': 'column', gap: '8px' } },
            h('div', { class: 'v2-row v2-spread' }, h('b', null, t.name), h('span', { class: 'v2-pill' + (t.state === 'open' ? ' warn' : '') }, t.state === 'open' ? 'Open to join' : t.state === 'running' ? `Round ${t.round}` : 'Finished')),
            h('div', { class: 'v2-note' }, `${t.players.length} / ${t.size} players${t.champion ? ' · Champion: ' + t.champion : ''}`),
            t.state === 'open' && !t.joined ? h('button', { class: 'v2-btn primary small', onclick: async e => { const r = await post('btJoinTourney', {}); if (r && r.ok) { e.target.textContent = 'Joined'; e.target.disabled = true; } } }, 'Join') : (t.joined ? h('span', { class: 'v2-tag' }, 'You’re in') : null),
            (t.rounds || []).map((rd, i) => h('div', { class: 'v2-note' }, h('b', null, `Round ${i + 1}: `), rd.map(m => `${m.a} v ${m.b}${m.winner ? ' → ' + m.winner : ''}`).join('  ·  ')))) : null;
        const last = (d.last || []).length ? h('div', { class: 'v2-note' }, 'Last season: ' + d.last.map((r, i) => `${i + 1}. ${r.name} (${r.points})`).join('   ')) : null;
        screen('', 'v2', topBar('Card battles', `Season ${d.season} · ends in ${dur(d.endsIn)}`),
            h('div', { class: 'v2-body' }, last,
                rows.length ? h('table', { class: 'v2-table' }, h('tr', null, h('th', null, '#'), h('th', null, 'Player'), h('th', null, 'Rank'), h('th', { class: 'num' }, 'W-L'), h('th', { class: 'num' }, 'Points')), rows)
                    : h('div', { class: 'v2-note' }, 'Nobody has played a ranked match this season yet. Set up a battle table and be first.')),
            h('div', { class: 'v2-side' },
                h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Your rank · ' + me.name), h('div', { class: 'v2-big' }, me.tier.name),
                    h('div', { class: 'v2-bar', style: { 'margin-top': '8px' } }, h('i', { style: { width: (me.tier.span ? pct(me.tier.into, me.tier.span) : 100) + '%' } })),
                    h('div', { class: 'v2-note', style: { 'margin-top': '8px' } }, `${me.points} points · ${me.wins} wins, ${me.losses} losses · #${me.pos}${me.tier.next ? ` · ${me.tier.next - me.points} to ${me.tier.nextLabel}` : ''}`)),
                tourney, h('div', { class: 'v2-label' }, 'Tiers'), tierRows,
                h('div', { class: 'v2-note' }, 'A win gives rank points and the wager. There are no pack prizes. Leaderboard names are character names.')));
    };

    /* ================================================================ BATTLE */
    let bt = null;
    const btTick = setInterval(() => {
        if (!bt || bt.over) return;
        const now = Date.now();
        const t = document.querySelector('.bt-timer'); if (t && bt.deadlineAt) t.textContent = String(Math.max(0, Math.ceil((bt.deadlineAt - now) / 1000)));
        const m = document.querySelector('.bt-match'); if (m && bt.matchAt) m.textContent = mmss((bt.matchAt - now) / 1000);
    }, 250);
    void btTick;

    handlers.btStart = d => {
        bt = { start: d, turn: null, reveal: null, end: null, over: false, picked: null, oppPicked: false, intro: true, deadlineAt: 0, matchAt: Date.now() + (d.matchLeft || 0) * 1000, life: { me: d.life, opp: d.life }, log: [], field: { mine: [], theirs: [] }, hand: [], handCount: { me: 0, opp: 0 }, deck: {} };
        btRender();
        setTimeout(() => { if (bt) { bt.intro = false; btRender(); } }, 1700);
    };
    handlers.btTurn = d => {
        if (!bt) return;
        bt.turn = d; bt.reveal = null; bt.picked = d.picked ? -1 : null; bt.oppPicked = !!d.oppPicked;
        bt.life = d.life; bt.log = d.log || []; bt.field = d.field; bt.hand = d.hand || []; bt.handCount = d.handCount; bt.deck = d.deck;
        bt.deadlineAt = Date.now() + (d.deadline || 0) * 1000; bt.matchAt = Date.now() + (d.matchLeft || 0) * 1000;
        bt.watch = !!d.watch; bt.names = d.names; bt.role = d.role;
        btRender();
    };
    handlers.btPicked = () => { if (bt) { bt.oppPicked = true; btRender(); } };
    handlers.btReveal = d => {
        if (!bt) return;
        bt.reveal = d; bt.life = d.life; bt.log = d.log || bt.log; bt.field = d.field; bt.deadlineAt = 0;
        btRender(true);
    };
    handlers.btEnd = d => { if (!bt) return; bt.end = d; bt.over = true; bt.endAt = Date.now() + (d.watch ? 600 : 3200); setTimeout(() => btRender(), d.watch ? 600 : 3200); };

    function btMat(m) {
        const s = { background: (m && m.bg) || '#12182a' };
        if (m && m.image) { s['background-image'] = `url(${m.image})`; s['background-size'] = m.imageFit === 'contain' ? 'contain' : 'cover'; s['background-repeat'] = 'no-repeat'; s['background-position'] = 'center'; }
        if (m && m.style && m.style.border) s['border-color'] = m.style.border;
        return s;
    }
    function btField(list, mat) {
        const slots = [];
        for (let i = 0; i < 5; i++) {
            const c = list[i];
            slots.push(h('div', { class: 'bt-slot', style: { 'border-color': (mat && mat.slot) || undefined } }, c ? mini(c.display, 90) : null));
        }
        return h('div', { class: 'bt-field' }, slots);
    }
    function lifeBox(name, rank, life, max, me, tint) {
        const p = pct(life, max);
        return h('div', { class: 'bt-player' },
            h('div', { class: 'v2-row' }, h('div', { class: 'bt-avatar' + (me ? ' me' : '') }, (name || '?').charAt(0).toUpperCase()),
                h('div', null, h('div', { style: { 'font-weight': 700 } }, name), h('div', { class: 'v2-note' }, rank || ''))),
            h('div', null, h('div', { class: 'v2-row v2-spread', style: { 'align-items': 'baseline' } }, h('span', { class: 'v2-label' }, 'Life'), h('span', { class: 'v2-big', style: { 'font-size': '30px' } }, String(life))),
                h('div', { class: 'bt-life' }, h('i', { style: { width: p + '%', background: tint || (p > 50 ? '#3aa56b' : p > 25 ? '#7aa7ff' : '#d6453d') } }))));
    }

    function btRender(reveal) {
        if (!bt) return;
        const st = bt.start, t = bt.turn, rv = bt.reveal;
        const watch = !!st.watch;
        const maxLife = st.life;
        const hand = bt.hand || [];
        const mineMat = st.mats && st.mats.mine, theirMat = st.mats && st.mats.theirs;
        const canPick = t && !rv && !bt.picked && !watch && !bt.over;
        const youAtk = t && t.role === 'attack';

        let status;
        if (rv) status = h('div', { class: 'pill' }, h('span', { class: 'v2-note' }, rv.line));
        else if (!t) status = h('div', { class: 'pill' }, 'Shuffling…');
        else if (watch) status = h('div', { class: 'pill' }, `${t.attackerName} is attacking. Waiting for both picks…`);
        else if (bt.picked) status = h('div', { class: 'pill' }, bt.oppPicked ? 'Revealing…' : 'Locked in. Waiting for your opponent…');
        else status = h('div', { class: 'pill' }, h('b', { style: { color: youAtk ? '#ff8a80' : '#7db4ee' } }, youAtk ? 'You attack' : 'You defend'), h('span', { class: 'v2-note' }, youAtk ? 'Pick your strongest ATT.' : 'Pick your best DEF.'));

        let clash = null;
        if (rv) {
            const aMine = rv.youAttack;
            clash = h('div', { class: 'bt-clash', style: { 'justify-content': 'center' } },
                h('div', { style: { display: 'flex', 'flex-direction': 'column', 'align-items': 'center', gap: '4px' } }, mini(rv.atk.display, 110), h('b', { class: 'v2-att' }, `ATT ${rv.atk.att}`), h('span', { class: 'v2-note' }, aMine ? 'You' : (watch ? rv.attackerName : 'Opponent'))),
                h('div', { class: 'v2-big', style: { color: 'var(--v2-accent)' } }, 'VS'),
                h('div', { style: { display: 'flex', 'flex-direction': 'column', 'align-items': 'center', gap: '4px' } }, mini(rv.def.display, 110), h('b', { class: 'v2-def' }, `DEF ${rv.def.def}`), h('span', { class: 'v2-note' }, aMine ? 'Opponent' : 'You')));
        }
        const clashRow = h('div', { class: 'bt-clash' }, h('div', { class: 'ln' }), status, h('div', { class: 'ln' }));

        const handEl = h('div', { class: 'bt-hand' }, watch ? h('div', { class: 'v2-note' }, 'You are watching this match.') : hand.map(c => {
            const sel = bt.picked === c.uid;
            const stats = youAtk ? [['att', c.att]] : [['def', c.def]];
            const el = h('div', { class: 'bt-hcard' + (sel ? ' sel' : '') + (canPick ? '' : ' locked'), title: `${c.display.label} · ATT ${c.att} DEF ${c.def}${c.pos ? ' · ' + c.pos : ''}`, onclick: () => { if (!canPick) return; bt.picked = c.uid; post('btPick', { uid: c.uid }); btRender(); } },
                mini(c.display, 108),
                h('div', { class: 'bt-st' }, h('b', { class: 'v2-att' }, String(c.att)), h('b', { class: 'v2-def' }, String(c.def))));
            return el;
        }));

        const oppBacks = h('div', { class: 'bt-field' }, Array.from({ length: bt.handCount ? bt.handCount.opp : 0 }, () => h('div', { class: 'bt-oppcard' })));

        const stage = h('div', { class: 'bt-stage' },
            h('div', { class: 'bt-half', style: btMat(theirMat) }, h('div', { class: 'mid', style: { background: (theirMat && theirMat.line) || '#fff' } }), oppBacks, btField(bt.field.theirs || [], theirMat)),
            rv ? clash : clashRow,
            rv ? clashRow : null,
            h('div', { class: 'bt-half', style: btMat(mineMat) }, h('div', { class: 'mid', style: { background: (mineMat && mineMat.line) || '#fff' } }), btField(bt.field.mine || [], mineMat), handEl));
        if (rv && rv.damage > 0) stage.appendChild(h('div', { class: 'bt-dmg' }, `-${rv.damage}`));
        else if (rv) stage.appendChild(h('div', { class: 'bt-dmg block' }, 'BLOCKED'));

        const left = h('div', { class: 'bt-left' },
            lifeBox(st.opp.name, st.opp.rank, bt.life.opp, maxLife, false, theirMat && theirMat.style && theirMat.style.hpOpp),
            h('div', { class: 'v2-note', style: { 'text-align': 'center' } }, st.pot > 0 ? `Pot ${money(st.pot)}` : 'Friendly match', h('br'), st.ranked === false ? 'Unranked' : `Season ${st.season}`, st.tourney ? h('div', null, st.tourney) : null),
            lifeBox(st.me.name, st.me.rank, bt.life.me, maxLife, true, mineMat && mineMat.style && mineMat.style.hpYou));

        const right = h('div', { class: 'bt-right' },
            h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Match time left'), h('div', { class: 'v2-big bt-match' }, mmss((bt.matchAt - Date.now()) / 1000)),
                h('div', { class: 'v2-note' }, `Deck ${bt.deck && bt.deck.me != null ? bt.deck.me : '-'} · Opp deck ${bt.deck && bt.deck.opp != null ? bt.deck.opp : '-'}`)),
            h('div', { class: 'v2-label' }, 'Battle log'),
            h('div', { class: 'bt-log' }, (bt.log || []).slice().reverse().map(l => h('div', null, l))),
            watch ? h('button', { class: 'v2-btn', onclick: () => { post('btUnwatch', {}); post('btDone', {}); bt = null; } }, 'Stop watching')
                : h('button', { class: 'v2-btn danger', onclick: () => { if (bt && !bt.confirmFF) { bt.confirmFF = true; btRender(); return; } post('btForfeit', {}); } }, bt.confirmFF ? 'Really forfeit?' : 'Forfeit'));

        const top = h('div', { class: 'v2-top' },
            h('div', { class: 'v2-row' }, h('h1', null, watch ? 'Watching' : 'Card battle'), h('div', { class: 'bt-phases' }, h('span', { class: 'bt-phase' + (!rv ? ' on' : ' done') }, 'Pick'), h('span', { class: 'bt-phase' + (rv ? ' on' : '') }, 'Reveal'))),
            h('div', { class: 'v2-row' }, h('span', { class: 'v2-sub' }, t ? `Turn ${t.turn}` : ''), h('div', { class: 'bt-timer' }, bt.deadlineAt && !rv ? String(Math.max(0, Math.ceil((bt.deadlineAt - Date.now()) / 1000))) : '')));

        host.clear();
        host.setMode('v2lock');
        const el = h('div', { class: 'v2 bt' }, top, h('div', { class: 'v2-main' }, left, stage, right));
        if (bt.intro) el.appendChild(h('div', { class: 'bt-intro' }, h('div', null, st.me.name, h('small', null, st.me.rank)), h('div', { class: 'vs' }, 'VS'), h('div', null, st.opp.name, h('small', null, st.opp.rank))));
        if (bt.over && bt.end && bt.endShown !== false && (!rv || Date.now() > (bt.endAt || 0))) {
            const e = bt.end;
            const title = e.watch ? (e.outcome === 'draw' ? 'DRAW' : (e.winnerName || '') + ' WINS') : e.outcome === 'win' ? 'VICTORY' : e.outcome === 'lose' ? 'DEFEAT' : 'DRAW';
            const why = { ko: 'Knockout.', time: 'Time ran out: highest life wins.', forfeit: e.forfeit ? 'Your opponent forfeited.' : 'Match forfeited.', table: 'The table was picked up. Wagers returned.' }[e.why] || '';
            const r = e.rank;
            el.appendChild(h('div', { class: 'bt-end ' + (e.watch ? 'draw' : e.outcome) },
                h('div', { class: 't' }, title), h('div', { class: 'v2-note' }, why),
                !e.watch && e.pot > 0 ? h('div', { style: { 'font-size': '18px' } }, e.outcome === 'win' ? `You won ${money(e.pot)}` : e.outcome === 'lose' ? `You lost ${money(e.bet)}` : 'Wagers returned') : null,
                r && r.ranked ? h('div', { class: 'v2-card', style: { 'min-width': '260px' } }, h('div', { class: 'v2-label' }, 'Rank points'), h('div', { class: 'v2-big ' + (r.delta >= 0 ? 'v2-up' : 'v2-down') }, (r.delta >= 0 ? '+' : '') + r.delta), h('div', { class: 'v2-note' }, `${r.tier.name} · ${r.after} points`)) : (r ? h('div', { class: 'v2-note' }, 'Unranked match: you played this opponent too many times today.') : null),
                h('button', { class: 'v2-btn primary', onclick: () => { post('btDone', {}); bt = null; } }, 'Back to the table')));
        }
        root.appendChild(el);
    }

    /* ================================================================ TRADER */
    let tr = null;
    handlers.trader = d => { tr = { data: d, tab: 'quantity', sel: new Set(), rate: null, target: null }; trRender(); };
    async function trRefresh(msg, kind) {
        const r = await post('traderRefresh', {});
        if (r && r.ok) { tr.data = r.data; tr.sel = new Set(); tr.rate = null; tr.target = null; trRender(msg, kind); }
        else host.close();
    }
    function pickGrid(cards, need, toggle) {
        return h('div', { class: 'dk-pocket' }, cards.map(c => {
            const on = tr.sel.has(c.serial);
            return h('div', { class: 'dk-cell', style: on ? { outline: '2px solid var(--v2-accent)' } : {}, onclick: () => toggle(c) }, mini(c.display, 100),
                h('span', { class: on ? 'v2-tag' : 'v2-tag mute' }, on ? 'Handing over' : (c.cond != null ? `Cond ${c.cond}` : 'Select')));
        }));
    }
    function trToggle(c, need) {
        if (tr.sel.has(c.serial)) tr.sel.delete(c.serial);
        else if (tr.sel.size < need) tr.sel.add(c.serial);
        trRender();
    }
    async function trDo(kind, payload) {
        const r = await post('traderSwap', { kind, payload });
        if (r && r.ok) {
            const x = r.data;
            await trRefresh(kind === 'condition' ? `${x.title} restored: condition ${x.before} to ${x.after}.` : `You got ${x.title}.`, 'ok');
        } else toast(root.firstChild, (r && r.error) || 'The trader said no.', 'err');
    }
    function trRender(msg, kind) {
        const d = tr.data, lbl = id => d.types[id] || id;
        const left = d.limit - d.used;
        const tabs = [['quantity', 'Quantity'], ['condition', 'Condition'], ['sidegrade', 'Sidegrade']];
        if (d.wantsOn) tabs.push(['wants', 'Collector wants']);
        const tabEl = h('div', { class: 'v2-chips' }, tabs.map(([id, name]) => h('button', { class: 'v2-chip' + (tr.tab === id ? ' on' : ''), onclick: () => { tr.tab = id; tr.sel = new Set(); tr.rate = null; tr.target = null; trRender(); } }, name)));
        const plain = d.cards.filter(c => c.plain || !d.plainOnly);
        let body;
        if (tr.tab === 'quantity') {
            const rates = d.rates.quantity;
            const rate = rates.find(r => r.from === tr.rate);
            const cards = rate ? plain.filter(c => c.type === rate.from) : [];
            body = [h('div', { class: 'v2-note' }, 'Hand over a stack of one type and get one card of the next type up. Plain cards only. Rates change every day.'),
                h('div', { class: 'v2-row', style: { 'flex-wrap': 'wrap' } }, rates.map(r => h('button', { class: 'v2-chip' + (tr.rate === r.from ? ' on' : ''), onclick: () => { tr.rate = r.from; tr.sel = new Set(); trRender(); } }, `${r.give} × ${lbl(r.from)} → 1 ${lbl(r.to)}`))),
                rate ? [h('div', { class: 'v2-row v2-spread' }, h('b', null, `Pick ${rate.give} ${lbl(rate.from)} cards (${tr.sel.size}/${rate.give})`), h('button', { class: 'v2-btn primary' + (tr.sel.size === rate.give ? '' : ' off'), onclick: () => trDo('quantity', { from: rate.from, serials: [...tr.sel] }) }, 'Swap')),
                    cards.length ? pickGrid(cards, rate.give, c => trToggle(c, rate.give)) : h('div', { class: 'v2-note' }, `You have no plain ${lbl(rate.from)} cards on you.`)] : null];
        } else if (tr.tab === 'sidegrade') {
            const rates = d.rates.sidegrade;
            const rate = rates.find(r => r.type === tr.rate);
            const cards = rate ? plain.filter(c => c.type === rate.type) : [];
            body = [h('div', { class: 'v2-note' }, 'Swap for a different card of the same type. Hot types swap one for one.'),
                h('div', { class: 'v2-row', style: { 'flex-wrap': 'wrap' } }, rates.map(r => h('button', { class: 'v2-chip' + (tr.rate === r.type ? ' on' : ''), onclick: () => { tr.rate = r.type; tr.sel = new Set(); trRender(); } }, `${r.give} × ${lbl(r.type)} → 1 different${r.hot ? '  ★ hot' : ''}`))),
                rate ? [h('div', { class: 'v2-row v2-spread' }, h('b', null, `Pick ${rate.give} (${tr.sel.size}/${rate.give})`), h('button', { class: 'v2-btn primary' + (tr.sel.size === rate.give ? '' : ' off'), onclick: () => trDo('sidegrade', { type: rate.type, serials: [...tr.sel] }) }, 'Swap')),
                    cards.length ? pickGrid(cards, rate.give, c => trToggle(c, rate.give)) : h('div', { class: 'v2-note' }, `You have no plain ${lbl(rate.type)} cards on you.`)] : null];
        } else if (tr.tab === 'condition') {
            const need = d.rates.condition.dupes;
            const targets = d.cards.filter(c => c.cond != null && c.cond < 10);
            const target = targets.find(c => c.serial === tr.target);
            const dupes = target ? plain.filter(c => c.cardId === target.cardId && c.serial !== target.serial) : [];
            body = [h('div', { class: 'v2-note' }, `Hand over ${need} other copies of the same card to restore one copy by ${d.rates.condition.steps} steps on centring, corners, edges and surface. Removes dust, dirt and stains.`),
                h('div', { class: 'v2-label' }, '1. Choose the card to restore'),
                targets.length ? h('div', { class: 'dk-pocket' }, targets.map(c => h('div', { class: 'dk-cell', style: tr.target === c.serial ? { outline: '2px solid var(--v2-accent)' } : {}, onclick: () => { tr.target = c.serial; tr.sel = new Set(); trRender(); } }, mini(c.display, 100), h('span', { class: 'v2-tag mute' }, `Cond ${c.cond}`)))) : h('div', { class: 'v2-note' }, 'None of your cards need restoring.'),
                target ? [h('div', { class: 'v2-row v2-spread' }, h('b', null, `2. Pick ${need} spare copies (${tr.sel.size}/${need})`), h('button', { class: 'v2-btn primary' + (tr.sel.size === need ? '' : ' off'), onclick: () => trDo('condition', { serial: target.serial, serials: [...tr.sel] }) }, 'Restore')),
                    dupes.length >= need ? pickGrid(dupes, need, c => trToggle(c, need)) : h('div', { class: 'v2-note' }, `You need ${need} more plain copies of this card.`)] : null];
        } else {
            const b = d.brand;
            body = [b ? h('div', { class: 'v2-pill warn' }, `Brand week: ${b.label} +${Math.round(b.bonus * 100)}%`) : null,
                h('div', { class: 'v2-note' }, 'The collector pays cash. Each want can be done once a day per player.'),
                d.wants.map(w => {
                    const need = w.kind === 'brand' ? w.count : 1;
                    const pool = w.kind === 'slab' ? d.slabs.filter(s => w.eligible.includes(s.serial)) : d.cards.filter(c => w.eligible.includes(c.serial));
                    const picked = (tr.wsel && tr.wsel[w.id]) || [];
                    const go = h('button', { class: 'v2-btn primary small' + (picked.length === need && !w.done ? '' : ' off'), onclick: async () => {
                        const r = await post('wantHand', { id: w.id, serials: picked });
                        if (r && r.ok) { tr.wsel = {}; await trRefresh(`The collector paid you ${money(r.data.pay)}.`, 'ok'); } else toast(root.firstChild, (r && r.error) || 'No deal.', 'err');
                    } }, 'Hand over');
                    return h('div', { class: 'v2-card', style: { display: 'flex', 'flex-direction': 'column', gap: '10px', opacity: w.done ? .5 : 1 } },
                        h('div', { class: 'v2-row v2-spread' }, h('div', null, h('b', null, w.label), h('div', { class: 'v2-note' }, w.payNote + (w.value ? ` · market ${money(w.value)}` : ''))), w.done ? h('span', { class: 'v2-pill' }, 'Done today') : h('span', { class: 'v2-tag' }, `${w.have} of ${need} on you`)),
                        !w.done && pool.length ? h('div', { class: 'dk-pocket', style: { 'justify-content-items': 'start' } }, pool.map(c => {
                            const on = picked.includes(c.serial);
                            return h('div', { class: 'dk-cell', style: on ? { outline: '2px solid var(--v2-accent)' } : {}, onclick: () => {
                                tr.wsel = tr.wsel || {};
                                const cur = (tr.wsel[w.id] || []).slice();
                                const i = cur.indexOf(c.serial);
                                if (i >= 0) cur.splice(i, 1); else if (cur.length < need) cur.push(c.serial);
                                tr.wsel[w.id] = cur; trRender();
                            } }, mini(c.display, 84), h('span', { class: on ? 'v2-tag' : 'v2-tag mute' }, on ? 'Selected' : 'Select'));
                        })) : null,
                        w.done ? null : go);
                })];
        }
        const el = screen('', 'v2', topBar('Card trader', `${left} of ${d.limit} swaps left today · rates reset in ${dur(d.resetIn)}`),
            h('div', { class: 'v2-body' }, tabEl, body));
        if (msg) toast(el, msg, kind);
    }

    /* ================================================================ CARD SHOP: CUSTOMER */
    let cu = null;
    handlers.shopCustomer = d => { cu = { data: d, tab: 'buy', amt: {} }; cuRender(); };
    async function cuRefresh(msg) {
        const r = await post('shopRefreshCustomer', {});
        if (r && r.ok) { cu.data = r.data; cuRender(msg); } else host.close();
    }
    function cuRender(msg) {
        const d = cu.data;
        const tabs = h('div', { class: 'v2-chips' },
            h('button', { class: 'v2-chip' + (cu.tab === 'buy' ? ' on' : ''), onclick: () => { cu.tab = 'buy'; cuRender(); } }, 'Buy'),
            d.buying ? h('button', { class: 'v2-chip' + (cu.tab === 'sell' ? ' on' : ''), onclick: () => { cu.tab = 'sell'; cuRender(); } }, 'Sell to the shop') : null);
        let list;
        if (cu.tab === 'buy') {
            list = d.items.length ? d.items.map(r => {
                const amt = cu.amt[r.id] || 1;
                const qty = h('input', { class: 'v2-input', type: 'number', min: '1', max: String(r.qty), value: String(amt), style: { width: '70px' } });
                qty.addEventListener('keyup', e => e.stopPropagation());
                qty.addEventListener('input', () => { cu.amt[r.id] = Math.max(1, Math.min(r.qty, parseInt(qty.value) || 1)); });
                return h('div', { class: 'v2-listrow' },
                    r.display ? mini(r.display, 54) : null,
                    h('div', { class: 'v2-grow' }, h('div', { style: { 'font-weight': 600 } }, r.label), h('div', { class: 'v2-note' }, `${r.qty} in stock`)),
                    r.kind === 'item' ? qty : null,
                    h('b', { style: { width: '90px', 'text-align': 'right' } }, money(r.price)),
                    h('button', { class: 'v2-btn small primary', onclick: async () => { const x = await post('shopBuy', { id: r.id, amount: r.kind === 'item' ? (cu.amt[r.id] || 1) : 1 }); if (x && x.ok) { cu.amt[r.id] = 1; cuRefresh('Bought.'); } else toast(root.firstChild, (x && x.error) || 'Could not buy that.', 'err'); } }, 'Buy'));
            }) : [h('div', { class: 'v2-note' }, 'The shelves are empty right now.')];
        } else {
            list = d.sell.length ? d.sell.map(r => h('div', { class: 'v2-listrow' },
                r.display ? mini(r.display, 54) : null,
                h('div', { class: 'v2-grow' }, h('div', { style: { 'font-weight': 600 } }, r.title), h('div', { class: 'v2-note' }, `Market ${money(r.market)}`)),
                h('b', { style: { width: '90px', 'text-align': 'right', color: '#6fd39a' } }, money(r.offer)),
                h('button', { class: 'v2-btn small', onclick: async () => { const x = await post('shopSell', { slot: r.slot, serial: r.serial }); if (x && x.ok) cuRefresh('Sold.'); else toast(root.firstChild, (x && x.error) || 'They said no.', 'err'); } }, 'Sell'))) : [h('div', { class: 'v2-note' }, 'You have nothing the shop will buy.')];
        }
        const el = screen('', 'v2', topBar(d.shop, d.servedBy ? `Served by ${d.servedBy}` : 'Player run shop'),
            h('div', { class: 'v2-body' }, tabs, cu.tab === 'sell' ? h('div', { class: 'v2-note' }, `The shop pays ${Math.round(d.pct * 100)}% of market value.`) : null, list),
            h('div', { class: 'v2-side' }, h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Want a card graded?'), h('div', { class: 'v2-note', style: { 'margin-top': '6px' } }, d.grading ? 'Ask the member of staff at the counter to submit it for you.' : 'Grading is not offered here.')),
                h('div', { class: 'v2-note' }, 'Prices are set by the shop staff. Payments go to the shop till.')));
        if (msg) toast(el, msg, 'ok');
    }

    /* ================================================================ CARD SHOP: MANAGER */
    let mg = null;
    handlers.shopManage = d => { mg = { data: d, tab: 'stock', q: {} }; mgRender(); };
    async function mgDo(name, payload, okMsg) {
        const r = await post(name, payload);
        if (r && r.ok) { mg.data = r.data; mgRender(okMsg); } else toast(root.firstChild, (r && r.error) || 'Could not do that.', 'err');
    }
    const AGO = t => { const s = Math.max(0, Math.floor(Date.now() / 1000) - t); return s < 3600 ? Math.floor(s / 60) + 'm ago' : s < 86400 ? Math.floor(s / 3600) + 'h ago' : Math.floor(s / 86400) + 'd ago'; };
    const ROLE = { owner: 'Owner', manager: 'Manager', staff: 'Staff' };
    function mgRender(msg) {
        const d = mg.data;
        const tabs = [['stock', 'Stock and prices'], ['buy', 'Buy list'], ['staff', 'Staff'], ['ledger', 'Ledger']];
        if (d.canOrder) tabs.push(['wholesale', 'Wholesale']);
        const tabEl = h('div', { class: 'v2-chips' }, tabs.map(([id, n]) => h('button', { class: 'v2-chip' + (mg.tab === id ? ' on' : ''), onclick: () => { mg.tab = id; mgRender(); } }, n)));
        const num = (val, w) => { const i = h('input', { class: 'v2-input', type: 'number', value: String(val), style: { width: (w || 110) + 'px' } }); i.addEventListener('keyup', e => e.stopPropagation()); return i; };
        let body;
        if (mg.tab === 'stock') {
            body = [h('table', { class: 'v2-table' }, h('tr', null, h('th', null, 'Item'), h('th', { class: 'num' }, 'In stock'), h('th', { class: 'num' }, 'Market'), h('th', { class: 'num' }, 'You sell at'), h('th', { class: 'num' }, 'Margin')),
                d.items.map(r => {
                    const inp = num(r.price, 100);
                    const save = () => { const v = parseInt(inp.value); if (v !== r.price) mgDo('shopSetPrice', { id: r.id, price: v }, 'Price saved.'); };
                    if (d.canPrice) { inp.addEventListener('keyup', e => { if (e.key === 'Enter') save(); }); inp.addEventListener('change', save); }
                    const mar = r.price - r.market;
                    return h('tr', null, h('td', { style: { 'font-weight': 600 } }, r.label, r.kind === 'card' ? h('span', { class: 'v2-tag mute', style: { 'margin-left': '8px' } }, 'single') : null),
                        h('td', { class: 'num' }, String(r.qty)), h('td', { class: 'num', style: { color: 'var(--v2-muted)' } }, money(r.market)),
                        h('td', { class: 'num' }, d.canPrice ? inp : money(r.price), h('div', { class: 'v2-note' }, `${money(r.min)} – ${money(r.max)}`)),
                        h('td', { class: 'num ' + (mar > 0 ? 'v2-up' : '') }, (mar >= 0 ? '+' : '-') + money(Math.abs(mar))));
                })),
                h('div', { class: 'v2-note' }, `Prices must stay within ${Math.round(d.sellMin * 100)}% to ${Math.round(d.sellMax * 100)}% of market. ${d.canPrice ? 'Edit a price and press Enter.' : 'Only managers and the owner change prices.'}`)];
        } else if (mg.tab === 'buy') {
            const rng = h('input', { type: 'range', min: String(d.buyMin * 100), max: String(d.buyMax * 100), step: '5', value: String(Math.round(d.pct * 100)), style: { width: '320px' }, disabled: d.canPrice ? undefined : 'disabled' });
            const lbl = h('b', null, Math.round(d.pct * 100) + '%');
            rng.addEventListener('input', () => { lbl.textContent = rng.value + '%'; });
            body = [h('div', { class: 'v2-card', style: { display: 'flex', 'flex-direction': 'column', gap: '12px' } },
                h('div', { class: 'v2-row v2-spread' }, h('b', null, 'Buying from players'), h('span', { class: 'v2-pill' + (d.buying ? '' : ' bad') }, d.buying ? 'On' : 'Off')),
                h('div', { class: 'v2-row' }, h('span', { class: 'v2-label' }, 'Pay players'), rng, lbl, h('span', { class: 'v2-label' }, 'of market')),
                h('div', { class: 'v2-note' }, `The shop can pay ${Math.round(d.buyMin * 100)}% to ${Math.round(d.buyMax * 100)}% of market. Cards bought go on your shelves at market price.`),
                d.canPrice ? h('div', { class: 'v2-row' }, h('button', { class: 'v2-btn primary', onclick: () => mgDo('shopSetBuy', { pct: parseInt(rng.value) / 100, on: d.buying }, 'Saved.') }, 'Save price'),
                    h('button', { class: 'v2-btn', onclick: () => mgDo('shopSetBuy', { pct: parseInt(rng.value) / 100, on: !d.buying }, d.buying ? 'Buying switched off.' : 'Buying switched on.') }, d.buying ? 'Switch buying off' : 'Switch buying on')) : null)];
        } else if (mg.tab === 'staff') {
            body = [h('div', { class: 'v2-label' }, 'On the server now'),
                d.staff.length ? d.staff.map(s => h('div', { class: 'v2-listrow' }, h('span', { class: 'v2-dot', style: { background: s.onduty ? '#3aa56b' : '#666' } }), h('span', { class: 'v2-grow', style: { 'font-weight': 600 } }, s.name), h('span', { class: 'v2-tag mute' }, ROLE[s.rank] || s.rank), h('span', { class: 'v2-note' }, s.onduty ? 'On duty' : 'Off duty'))) : h('div', { class: 'v2-note' }, 'Nobody from the shop is online.'),
                h('div', { class: 'v2-label', style: { 'margin-top': '10px' } }, 'Pay and sales'),
                d.stats.length ? h('table', { class: 'v2-table' }, h('tr', null, h('th', null, 'Name'), h('th', { class: 'num' }, 'Hours'), h('th', { class: 'num' }, 'Sales'), h('th', { class: 'num' }, 'Sold'), h('th', { class: 'num' }, 'Earned')),
                    d.stats.map(s => h('tr', null, h('td', null, s.name), h('td', { class: 'num' }, (s.minutes / 60).toFixed(1)), h('td', { class: 'num' }, String(s.sales)), h('td', { class: 'num' }, money(s.sold_value)), h('td', { class: 'num' }, money(s.earned))))) : h('div', { class: 'v2-note' }, 'No shifts recorded yet.'),
                h('div', { class: 'v2-note' }, `Pay: ${money(d.pay.hourly)} an hour plus ${Math.round((d.pay.commission || 0) * 100)}% commission, paid from the till. Hiring and firing is done through the job system.`)];
        } else if (mg.tab === 'ledger') {
            body = d.ledger.length ? h('table', { class: 'v2-table' }, h('tr', null, h('th', null, 'When'), h('th', null, 'Who'), h('th', null, 'What'), h('th', { class: 'num' }, 'Amount')),
                d.ledger.map(l => h('tr', null, h('td', { style: { color: 'var(--v2-muted)' } }, AGO(l.at)), h('td', null, l.name || ''), h('td', null, l.detail || l.kind), h('td', { class: 'num ' + (l.amount >= 0 ? 'v2-up' : 'v2-down') }, (l.amount >= 0 ? '+' : '-') + money(Math.abs(l.amount)))))) : h('div', { class: 'v2-note' }, 'Nothing in the ledger yet.');
        } else {
            body = [h('div', { class: 'v2-note' }, `Wholesale costs about ${Math.round((d.catalogue[0] ? d.catalogue[0].cost / d.catalogue[0].market : 0.7) * 100)}% of the shelf price and is paid from the till. Max ${d.maxPer} per order.`),
                d.catalogue.map(c => {
                    const q = num(10, 80);
                    return h('div', { class: 'v2-listrow' }, h('div', { class: 'v2-grow' }, h('div', { style: { 'font-weight': 600 } }, c.label), h('div', { class: 'v2-note' }, `Shelf price ${money(c.market)}`)), h('b', null, money(c.cost) + ' each'), q,
                        h('button', { class: 'v2-btn small primary', onclick: () => mgDo('shopOrder', { item: c.item, qty: parseInt(q.value) || 0 }, 'Ordered. Stock added to the shelves.') }, 'Order'));
                }), d.catalogue.length ? null : h('div', { class: 'v2-note' }, 'Nothing to order right now.')];
        }
        const amt = num('', 150); amt.placeholder = 'Amount';
        const side = h('div', { class: 'v2-side', style: { width: '340px' } },
            h('div', { class: 'v2-card' }, h('div', { class: 'v2-label' }, 'Shop till'), h('div', { class: 'v2-big', style: { 'font-size': '38px' } }, money(d.till)),
                h('div', { class: 'v2-note' }, `Last 24h: ${d.sold.n} sales for ${money(d.sold.v)} · ${d.bought} cards bought`)),
            h('div', { class: 'v2-pill' + (d.onDuty ? '' : ' warn') }, d.onDuty ? 'Shop open: NPC trader and shop are off' : 'Nobody on duty: NPC shop is open'),
            (d.canWithdraw || d.canPrice) ? h('div', { class: 'v2-card', style: { display: 'flex', 'flex-direction': 'column', gap: '10px' } }, h('div', { class: 'v2-label' }, 'Move money'), amt,
                h('div', { class: 'v2-row' }, d.canWithdraw ? h('button', { class: 'v2-btn small primary v2-grow', onclick: () => mgDo('shopWithdraw', { amount: parseInt(amt.value) || 0 }, 'Withdrawn to your bank.') }, 'Withdraw') : null,
                    d.canPrice ? h('button', { class: 'v2-btn small v2-grow', onclick: () => mgDo('shopDeposit', { amount: parseInt(amt.value) || 0 }, 'Added to the till.') }, 'Deposit') : null)) : null,
            h('div', { class: 'v2-note' }, 'Customers pay the till. Staff are paid hourly and earn commission on sales they serve.'),
            h('div', { class: 'v2-grow' }),
            h('button', { class: 'v2-btn', onclick: async () => { const r = await post('shopRefreshManage', {}); if (r && r.ok) { mg.data = r.data; mgRender('Refreshed.'); } } }, 'Refresh'));
        const el = screen('', 'v2', topBar('Card shop · ' + (ROLE[d.rank] || 'Staff'), d.name), h('div', { class: 'v2-body' }, tabEl, body), side);
        if (msg) toast(el, msg, 'ok');
    }
})();
