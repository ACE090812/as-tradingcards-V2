/* The card lying on the cleaning mat. Rendered into a DUI that replaces the prop's texture.
   Lua sends: { type: 'load', card, flip, size } then batches of { type: 'strokes', list: [...] }
   stroke: { t: 'w', x, y, r, s, g, w } wipe | { t: 'p', x, y, s } spray | { t: 's', x, y } scratch */
(() => {
    const box = document.getElementById('card');
    let ov = null;

    function fit(size, flip) {
        const sx = size / 300, sy = size / 420;
        // the prop's texture is stretched square and stored upside down
        box.style.transform = flip ? `translateY(${size}px) scale(${sx}, ${-sy})` : `scale(${sx}, ${sy})`;
    }

    function load(msg) {
        const R = window.ascardRender;
        box.innerHTML = '';
        const card = msg.card || {};
        box.appendChild(R.cardFace(card));
        ov = card.cond && card.cond.c ? window.CondFX.create(card.cond.c) : null;
        if (ov) box.appendChild(ov.el);
        fit(msg.size || window.innerWidth, msg.flip !== false);
    }

    function strokes(list) {
        if (!ov || !Array.isArray(list)) return;
        for (const s of list) {
            if (s.t === 'w') ov.erase(s.x, s.y, s.r, s.s, s.g, s.w);
            else if (s.t === 'p') ov.spray(s.x, s.y, s.s);
            else if (s.t === 's') ov.scratchAt(s.x, s.y);
        }
    }

    // droplets slowly dry
    setInterval(() => { if (ov) ov.dry(0.035); }, 250);

    window.addEventListener('message', e => {
        let msg = e.data;
        if (typeof msg === 'string') { try { msg = JSON.parse(msg); } catch (err) { return; } }
        if (!msg || typeof msg !== 'object') return;
        if (msg.type === 'load') load(msg);
        else if (msg.type === 'strokes') strokes(msg.list);
    });
})();
