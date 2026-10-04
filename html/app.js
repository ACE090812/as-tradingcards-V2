/* as-tradingcards v2 NUI - vanilla JS, no dependencies */
(() => {
    'use strict';

    const IN_GAME = typeof GetParentResourceName === 'function';
    const RES = IN_GAME ? GetParentResourceName() : 'as-tradingcards';
    const root = document.getElementById('root');
    const peekRoot = document.getElementById('peek-root');

    let mode = null;          // 'pack' | 'view' | 'binder' | null
    let peekTimer = null;

    /* ---------------------------------------------------------------- utils */
    function post(name, data = {}) {
        if (!IN_GAME) { console.log('[post]', name, data); return Promise.resolve(false); }
        return fetch(`https://${RES}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).then(r => r.json()).catch(() => false);
    }

    /* ----- sounds (html/sounds/*.ogg) ----- */
    let sfxCfg = { enabled: true, volume: 0.5, rip: 'snap', deal: 'dealfour', flip: 'flip', rare: 'badge', rareTypes: ['winner', 'century', 'legend'], box: 'boxopen' };
    const sfxCache = {};
    function sfx(name) {
        if (!sfxCfg.enabled || !name) return;
        try {
            const base = sfxCache[name] || (sfxCache[name] = new Audio(`sounds/${name}.ogg`));
            const a = base.cloneNode();
            a.volume = Math.max(0, Math.min(1, Number(sfxCfg.volume) || 0.5));
            a.play().catch(() => {});
        } catch (e) { /* no audio */ }
    }
    const isRare = card => card.foil || !!card.parallel || (Array.isArray(sfxCfg.rareTypes) && card.rarity && sfxCfg.rareTypes.includes(card.rarity.id));

    // tiny element builder (textContent only - no innerHTML from data)
    function h(tag, props, ...children) {
        const el = document.createElement(tag);
        if (props) {
            for (const [k, v] of Object.entries(props)) {
                if (v === undefined || v === null || v === false) continue;
                if (k === 'class') el.className = v;
                else if (k === 'style') {
                    for (const [sk, sv] of Object.entries(v)) el.style.setProperty(sk, sv);
                }
                else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
                else el.setAttribute(k, v);
            }
        }
        for (const c of children.flat(Infinity)) {
            if (c === null || c === undefined || c === false) continue;
            el.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
        }
        return el;
    }

    const isHigh = card => {
        const fx = (card.rarity && card.rarity.effects) || {};
        return !!(fx.glitter || fx.holo || fx.glow || fx.sweep) || card.foil || !!card.parallel;
    };

    function printText(card) {
        if (!card.print) return '';
        return card.maxPrints ? `#${card.print}/${card.maxPrints}` : `#${card.print}`;
    }

    // colours come from config; still only let plain colour values into SVG markup
    const COLOR_RE = /^(#[0-9a-fA-F]{3,8}|rgba?\([0-9.,\s%]+\))$/;
    const col = (v, fb) => (typeof v === 'string' && COLOR_RE.test(v.trim()) ? v.trim() : fb);
    const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function svgEl(markup, cls) {
        const wrap = document.createElement('div');
        wrap.innerHTML = markup;
        const svg = wrap.firstElementChild;
        if (cls) svg.setAttribute('class', cls);
        return svg;
    }

    /* ----- flags (simplified) ----- */
    const FLAGS = {
        ENG: '<rect width="30" height="20" fill="#fff"/><rect x="13" width="4" height="20" fill="#ce1124"/><rect y="8" width="30" height="4" fill="#ce1124"/>',
        SCO: '<rect width="30" height="20" fill="#005eb8"/><path d="M0 0L30 20M30 0L0 20" stroke="#fff" stroke-width="3.5"/>',
        NOR: '<rect width="30" height="20" fill="#ba0c2f"/><rect x="8" width="6" height="20" fill="#fff"/><rect y="7" width="30" height="6" fill="#fff"/><rect x="9.5" width="3" height="20" fill="#00205b"/><rect y="8.5" width="30" height="3" fill="#00205b"/>',
        POR: '<rect width="30" height="20" fill="#da291c"/><rect width="12" height="20" fill="#046a38"/><circle cx="12" cy="10" r="3.5" fill="#ffe900"/>',
        EGY: '<rect width="30" height="7" fill="#ce1126"/><rect y="7" width="30" height="6" fill="#fff"/><rect y="13" width="30" height="7" fill="#000"/><circle cx="15" cy="10" r="2" fill="#c09300"/>',
        NED: '<rect width="30" height="7" fill="#ae1c28"/><rect y="7" width="30" height="6" fill="#fff"/><rect y="13" width="30" height="7" fill="#21468b"/>',
        GER: '<rect width="30" height="7" fill="#000"/><rect y="7" width="30" height="6" fill="#dd0000"/><rect y="13" width="30" height="7" fill="#ffce00"/>',
        FRA: '<rect width="10" height="20" fill="#002395"/><rect x="10" width="10" height="20" fill="#fff"/><rect x="20" width="10" height="20" fill="#ed2939"/>',
        ARG: '<rect width="30" height="20" fill="#74acdf"/><rect y="7" width="30" height="6" fill="#fff"/><circle cx="15" cy="10" r="2" fill="#f6b40e"/>',
        ECU: '<rect width="30" height="10" fill="#ffdd00"/><rect y="10" width="30" height="5" fill="#034ea2"/><rect y="15" width="30" height="5" fill="#ed1c24"/>',
        CIV: '<rect width="10" height="20" fill="#f77f00"/><rect x="10" width="10" height="20" fill="#fff"/><rect x="20" width="10" height="20" fill="#009e60"/>',
        BEL: '<rect width="10" height="20" fill="#000"/><rect x="10" width="10" height="20" fill="#fdda24"/><rect x="20" width="10" height="20" fill="#ef3340"/>',
        BRA: '<rect width="30" height="20" fill="#009c3b"/><path d="M15 2L28 10L15 18L2 10Z" fill="#ffdf00"/><circle cx="15" cy="10" r="4.2" fill="#002776"/>',
        ITA: '<rect width="10" height="20" fill="#009246"/><rect x="10" width="10" height="20" fill="#fff"/><rect x="20" width="10" height="20" fill="#ce2b37"/>',
        ESP: '<rect width="30" height="20" fill="#aa151b"/><rect y="5" width="30" height="10" fill="#f1bf00"/>',
        POL: '<rect width="30" height="10" fill="#fff"/><rect y="10" width="30" height="10" fill="#dc143c"/>',
        MAR: '<rect width="30" height="20" fill="#c1272d"/><path d="M15 5.5L16.8 11.2L12.1 7.7H17.9L13.2 11.2Z" fill="none" stroke="#006233" stroke-width="0.9"/>',
        AFG: '<rect x="0.00" width="10.05" height="20" fill="#000"/><rect x="10.00" width="10.05" height="20" fill="#d32011"/><rect x="20.00" width="10.05" height="20" fill="#007a36"/>',
        ALB: '<rect width="30" height="20" fill="#e41e20"/><circle cx="15" cy="10" r="5" fill="#000"/>',
        ALG: '<rect x="0.00" width="15.05" height="20" fill="#006233"/><rect x="15.00" width="15.05" height="20" fill="#fff"/><circle cx="15" cy="10" r="5" fill="#d21034"/><circle cx="16.5" cy="10" r="4" fill="#fff"/><path d="M17.5 8L18.68 11.62L15.60 9.38H19.40L16.32 11.62Z" fill="#d21034"/>',
        AUS: '<rect width="30" height="20" fill="#012169"/><rect width="15" height="10" fill="#012169"/><path d="M0 0L15 10M15 0L0 10" stroke="#fff" stroke-width="2"/><path d="M7.5 0V10M0 5H15" stroke="#fff" stroke-width="3"/><path d="M7.5 0V10M0 5H15" stroke="#c8102e" stroke-width="1.6"/><path d="M7.5 12.6L8.92 16.94L5.22 14.26H9.78L6.08 16.94Z" fill="#fff"/><path d="M23 3.6L23.83 6.13L21.67 4.57H24.33L22.17 6.13Z" fill="#fff"/><path d="M20 9.6L20.83 12.13L18.67 10.57H21.33L19.17 12.13Z" fill="#fff"/><path d="M26 8.6L26.83 11.13L24.67 9.57H27.33L25.17 11.13Z" fill="#fff"/><path d="M23 14.6L23.83 17.13L21.67 15.57H24.33L22.17 17.13Z" fill="#fff"/>',
        AUT: '<rect y="0.00" width="30" height="6.72" fill="#ed2939"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#ed2939"/>',
        BEN: '<rect width="30" height="20" fill="#fcd116"/><rect y="10" width="30" height="10" fill="#e8112d"/><rect width="12" height="20" fill="#008751"/>',
        BER: '<rect width="30" height="20" fill="#c8102e"/><rect width="13" height="9" fill="#012169"/><path d="M0 0L13 9M13 0L0 9" stroke="#fff" stroke-width="1.6"/><path d="M6.5 0V9M0 4.5H13" stroke="#fff" stroke-width="2.4"/><path d="M6.5 0V9M0 4.5H13" stroke="#c8102e" stroke-width="1.2"/>',
        BFA: '<rect y="0.00" width="30" height="10.05" fill="#ef2b2d"/><rect y="10.00" width="30" height="10.05" fill="#009e49"/><path d="M15 6.8L16.89 12.59L11.96 9.01H18.04L13.11 12.59Z" fill="#fcd116"/>',
        BIH: '<rect width="30" height="20" fill="#002395"/><path d="M8 0H24V20Z" fill="#fecb00"/>',
        BRB: '<rect x="0.00" width="10.05" height="20" fill="#00267f"/><rect x="10.00" width="10.05" height="20" fill="#ffc726"/><rect x="20.00" width="10.05" height="20" fill="#00267f"/>',
        BUL: '<rect y="0.00" width="30" height="6.72" fill="#fff"/><rect y="6.67" width="30" height="6.72" fill="#00966e"/><rect y="13.33" width="30" height="6.72" fill="#d62612"/>',
        CAN: '<rect x="0.00" width="7.55" height="20" fill="#d52b1e"/><rect x="7.50" width="15.05" height="20" fill="#fff"/><rect x="22.50" width="7.55" height="20" fill="#d52b1e"/><path d="M15 4L16.3 7.5L18.5 6.5L17.5 11L19.5 10.5L15 15L10.5 10.5L12.5 11L11.5 6.5L13.7 7.5Z" fill="#d52b1e"/>',
        CHI: '<rect y="0.00" width="30" height="10.05" fill="#fff"/><rect y="10.00" width="30" height="10.05" fill="#d52b1e"/><rect width="10" height="10" fill="#0039a6"/><path d="M5 2L6.77 7.43L2.15 4.07H7.85L3.23 7.43Z" fill="#fff"/>',
        CMR: '<rect x="0.00" width="10.05" height="20" fill="#007a5e"/><rect x="10.00" width="10.05" height="20" fill="#ce1126"/><rect x="20.00" width="10.05" height="20" fill="#fcd116"/><path d="M15 7L16.77 12.43L12.15 9.07H17.85L13.23 12.43Z" fill="#fcd116"/>',
        COD: '<rect width="30" height="20" fill="#007fff"/><path d="M0 16L26 0H30V4L4 20H0Z" fill="#f7d618"/><path d="M0 17.5L28 0H30V2.5L2 20H0Z" fill="#ce1021"/><path d="M5 2L6.77 7.43L2.15 4.07H7.85L3.23 7.43Z" fill="#f7d618"/>',
        COL: '<rect y="0.00" width="30" height="10.05" fill="#fcd116"/><rect y="10.00" width="30" height="5.05" fill="#003893"/><rect y="15.00" width="30" height="5.05" fill="#ce1126"/>',
        CRO: '<rect y="0.00" width="30" height="6.72" fill="#ff0000"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#171796"/><rect x="11.5" y="5" width="7" height="8" fill="#fff" stroke="#ff0000" stroke-width="0.6"/><path d="M11.5 5h1.75v2h-1.75zM15 5h1.75v2H15zM13.25 7H15v2h-1.75zM16.75 7h1.75v2h-1.75zM11.5 9h1.75v2h-1.75zM15 9h1.75v2H15zM13.25 11H15v2h-1.75zM16.75 11h1.75v2h-1.75z" fill="#ff0000"/>',
        CUW: '<rect width="30" height="20" fill="#002b7f"/><rect y="13" width="30" height="2.5" fill="#f9e814"/><path d="M5 3.4L5.94 6.30L3.48 4.50H6.52L4.06 6.30Z" fill="#fff"/><path d="M9 5.8L10.30 9.78L6.91 7.32H11.09L7.70 9.78Z" fill="#fff"/>',
        CYP: '<rect width="30" height="20" fill="#fff"/><path d="M8 9C10 6 16 5 22 7C21 10 18 11 15 12C12 12 9 11 8 9Z" fill="#d57800"/><path d="M11 15Q15 17 19 15" stroke="#4e5b31" stroke-width="1.2" fill="none"/>',
        CZE: '<rect y="0.00" width="30" height="10.05" fill="#fff"/><rect y="10.00" width="30" height="10.05" fill="#d7141a"/><path d="M0 0L15 10L0 20Z" fill="#11457e"/>',
        DEN: '<rect width="30" height="20" fill="#c8102e"/><rect x="8" width="6" height="20" fill="#fff"/><rect y="7" width="30" height="6" fill="#fff"/>',
        EST: '<rect y="0.00" width="30" height="6.72" fill="#0072ce"/><rect y="6.67" width="30" height="6.72" fill="#000"/><rect y="13.33" width="30" height="6.72" fill="#fff"/>',
        FIN: '<rect width="30" height="20" fill="#fff"/><rect x="8" width="6" height="20" fill="#002f6c"/><rect y="7" width="30" height="6" fill="#002f6c"/>',
        GAB: '<rect y="0.00" width="30" height="6.72" fill="#009e60"/><rect y="6.67" width="30" height="6.72" fill="#fcd116"/><rect y="13.33" width="30" height="6.72" fill="#3a75c4"/>',
        GAM: '<rect y="0.00" width="30" height="6.72" fill="#ce1126"/><rect y="6.67" width="30" height="1.16" fill="#fff"/><rect y="7.78" width="30" height="4.49" fill="#0c1c8c"/><rect y="12.22" width="30" height="1.16" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#3a7728"/>',
        GEO: '<rect width="30" height="20" fill="#fff"/><rect x="13" width="4" height="20" fill="#ff0000"/><rect y="8" width="30" height="4" fill="#ff0000"/><path d="M6 3v4M4 5h4M24 3v4M22 5h4M6 13v4M4 15h4M24 13v4M22 15h4" stroke="#ff0000" stroke-width="1.2"/>',
        GHA: '<rect y="0.00" width="30" height="6.72" fill="#ce1126"/><rect y="6.67" width="30" height="6.72" fill="#fcd116"/><rect y="13.33" width="30" height="6.72" fill="#006b3f"/><path d="M15 7L16.77 12.43L12.15 9.07H17.85L13.23 12.43Z" fill="#000"/>',
        GNB: '<rect width="30" height="10" fill="#fcd116"/><rect y="10" width="30" height="10" fill="#009e49"/><rect width="11" height="20" fill="#ce1126"/><path d="M5.5 7.2L7.15 12.27L2.84 9.13H8.16L3.85 12.27Z" fill="#000"/>',
        GRE: '<rect y="0.00" width="30" height="2.27" fill="#0d5eaf"/><rect y="2.22" width="30" height="2.27" fill="#fff"/><rect y="4.44" width="30" height="2.27" fill="#0d5eaf"/><rect y="6.67" width="30" height="2.27" fill="#fff"/><rect y="8.89" width="30" height="2.27" fill="#0d5eaf"/><rect y="11.11" width="30" height="2.27" fill="#fff"/><rect y="13.33" width="30" height="2.27" fill="#0d5eaf"/><rect y="15.56" width="30" height="2.27" fill="#fff"/><rect y="17.78" width="30" height="2.27" fill="#0d5eaf"/><rect width="11" height="11.1" fill="#0d5eaf"/><rect x="4.4" width="2.2" height="11.1" fill="#fff"/><rect y="4.4" width="11" height="2.2" fill="#fff"/>',
        GUI: '<rect x="0.00" width="10.05" height="20" fill="#ce1126"/><rect x="10.00" width="10.05" height="20" fill="#fcd116"/><rect x="20.00" width="10.05" height="20" fill="#009460"/>',
        HAI: '<rect y="0.00" width="30" height="10.05" fill="#00209f"/><rect y="10.00" width="30" height="10.05" fill="#d21034"/><rect x="11" y="7" width="8" height="6" fill="#fff"/>',
        HUN: '<rect y="0.00" width="30" height="6.72" fill="#ce2939"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#477050"/>',
        IDN: '<rect y="0.00" width="30" height="10.05" fill="#ce1126"/><rect y="10.00" width="30" height="10.05" fill="#fff"/>',
        IRL: '<rect x="0.00" width="10.05" height="20" fill="#169b62"/><rect x="10.00" width="10.05" height="20" fill="#fff"/><rect x="20.00" width="10.05" height="20" fill="#ff883e"/>',
        ISL: '<rect width="30" height="20" fill="#02529c"/><rect x="8" width="6" height="20" fill="#fff"/><rect y="7" width="30" height="6" fill="#fff"/><rect x="9.5" width="3" height="20" fill="#dc1e35"/><rect y="8.5" width="30" height="3" fill="#dc1e35"/>',
        ISR: '<rect width="30" height="20" fill="#fff"/><rect y="2" width="30" height="3" fill="#0038b8"/><rect y="15" width="30" height="3" fill="#0038b8"/><path d="M15 6.5L18 11.7H12ZM15 13.5L12 8.3H18Z" fill="none" stroke="#0038b8" stroke-width="0.9"/>',
        JAM: '<rect width="30" height="20" fill="#009b3a"/><path d="M0 0L15 10L0 20ZM30 0L15 10L30 20Z" fill="#000"/><path d="M0 0L30 20M30 0L0 20" stroke="#fed100" stroke-width="3"/>',
        JOR: '<rect y="0.00" width="30" height="6.72" fill="#000"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#007a3d"/><path d="M0 0L14 10L0 20Z" fill="#ce1126"/>',
        JPN: '<rect width="30" height="20" fill="#fff"/><circle cx="15" cy="10" r="5.5" fill="#bc002d"/>',
        KEN: '<rect y="0.00" width="30" height="6.05" fill="#000"/><rect y="6.00" width="30" height="1.05" fill="#fff"/><rect y="7.00" width="30" height="6.05" fill="#bb0000"/><rect y="13.00" width="30" height="1.05" fill="#fff"/><rect y="14.00" width="30" height="6.05" fill="#006600"/><ellipse cx="15" cy="10" rx="3" ry="6" fill="#bb0000" stroke="#000" stroke-width="0.6"/>',
        KOR: '<rect width="30" height="20" fill="#fff"/><path d="M11 10A4 4 0 0 1 19 10Z" fill="#cd2e3a"/><path d="M11 10A4 4 0 0 0 19 10Z" fill="#0047a0"/><path d="M4 4l3 2M4 16l3-2M26 4l-3 2M26 16l-3-2" stroke="#000" stroke-width="1.4"/>',
        LCA: '<rect width="30" height="20" fill="#65cfff"/><path d="M15 3L21 17H9Z" fill="#fff"/><path d="M15 5L20 17H10Z" fill="#000"/><path d="M15 10L20 17H10Z" fill="#fcd116"/>',
        MEX: '<rect x="0.00" width="10.05" height="20" fill="#006847"/><rect x="10.00" width="10.05" height="20" fill="#fff"/><rect x="20.00" width="10.05" height="20" fill="#ce1126"/><circle cx="15" cy="10" r="2.2" fill="#8c5a2b"/>',
        MLI: '<rect x="0.00" width="10.05" height="20" fill="#14b53a"/><rect x="10.00" width="10.05" height="20" fill="#fcd116"/><rect x="20.00" width="10.05" height="20" fill="#ce1126"/>',
        MNE: '<rect width="30" height="20" fill="#d4af37"/><rect x="1.2" y="1.2" width="27.6" height="17.6" fill="#c40308"/><circle cx="15" cy="10" r="3.5" fill="#d4af37"/>',
        MOZ: '<rect y="0.00" width="30" height="6.72" fill="#007168"/><rect y="6.67" width="30" height="6.72" fill="#000"/><rect y="13.33" width="30" height="6.72" fill="#fce100"/><rect y="6.3" width="30" height="0.8" fill="#fff"/><rect y="12.9" width="30" height="0.8" fill="#fff"/><path d="M0 0L12 10L0 20Z" fill="#d21034"/>',
        NAM: '<rect width="30" height="20" fill="#009543"/><path d="M0 0H30L0 20Z" fill="#003580"/><path d="M0 20L26 0H30V0L4 20Z" fill="#fff"/><path d="M1.5 20L27.5 0H30L4 20Z" fill="#d21034"/><path d="M5 2.5L6.47 7.03L2.62 4.22H7.38L3.53 7.03Z" fill="#ffce00"/>',
        NGA: '<rect x="0.00" width="10.05" height="20" fill="#008751"/><rect x="10.00" width="10.05" height="20" fill="#fff"/><rect x="20.00" width="10.05" height="20" fill="#008751"/>',
        NIR: '<rect width="30" height="20" fill="#fff"/><rect x="13" width="4" height="20" fill="#c8102e"/><rect y="8" width="30" height="4" fill="#c8102e"/><path d="M15 7.5L16.48 12.03L12.62 9.22H17.38L13.53 12.03Z" fill="#fff"/><circle cx="15" cy="10.4" r="1.2" fill="#c8102e"/>',
        NZL: '<rect width="30" height="20" fill="#012169"/><path d="M0 0L15 10M15 0L0 10" stroke="#fff" stroke-width="2"/><path d="M7.5 0V10M0 5H15" stroke="#fff" stroke-width="3"/><path d="M7.5 0V10M0 5H15" stroke="#c8102e" stroke-width="1.6"/><path d="M23 3.4L23.94 6.30L21.48 4.50H24.52L22.06 6.30Z" fill="#c8102e"/><path d="M20 8.4L20.94 11.30L18.48 9.50H21.52L19.06 11.30Z" fill="#c8102e"/><path d="M26 7.4L26.94 10.30L24.48 8.50H27.52L25.06 10.30Z" fill="#c8102e"/><path d="M23 13.2L24.06 16.46L21.29 14.44H24.71L21.94 16.46Z" fill="#c8102e"/>',
        PAN: '<rect width="30" height="20" fill="#fff"/><rect x="15" width="15" height="10" fill="#d21034"/><rect y="10" width="15" height="10" fill="#005293"/><path d="M7.5 2.5L8.97 7.03L5.12 4.22H9.88L6.03 7.03Z" fill="#005293"/><path d="M22.5 12.5L23.98 17.02L20.12 14.22H24.88L21.02 17.02Z" fill="#d21034"/>',
        PAR: '<rect y="0.00" width="30" height="6.72" fill="#d52b1e"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#0038a8"/><circle cx="15" cy="10" r="2" fill="#fcd116"/>',
        PER: '<rect x="0.00" width="10.05" height="20" fill="#d91023"/><rect x="10.00" width="10.05" height="20" fill="#fff"/><rect x="20.00" width="10.05" height="20" fill="#d91023"/>',
        ROU: '<rect x="0.00" width="10.05" height="20" fill="#002b7f"/><rect x="10.00" width="10.05" height="20" fill="#fcd116"/><rect x="20.00" width="10.05" height="20" fill="#ce1126"/>',
        RSA: '<rect width="30" height="20" fill="#fff"/><rect width="30" height="10" fill="#e03c31"/><rect y="10" width="30" height="10" fill="#001489"/><path d="M0 0L12 10L0 20Z" fill="#ffb612"/><path d="M0 2.5L9 10L0 17.5Z" fill="#000"/><path d="M0 0H3L15 7H30V13H15L3 20H0L12 10Z" fill="#fff"/><path d="M0 1.5H1.5L14 8.5H30V11.5H14L1.5 18.5H0L11 10Z" fill="#007749"/>',
        SEN: '<rect x="0.00" width="10.05" height="20" fill="#00853f"/><rect x="10.00" width="10.05" height="20" fill="#fdef42"/><rect x="20.00" width="10.05" height="20" fill="#e31b23"/><path d="M15 7L16.77 12.43L12.15 9.07H17.85L13.23 12.43Z" fill="#00853f"/>',
        SLE: '<rect y="0.00" width="30" height="6.72" fill="#1eb53a"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#0072c6"/>',
        SRB: '<rect y="0.00" width="30" height="6.72" fill="#c6363c"/><rect y="6.67" width="30" height="6.72" fill="#0c4076"/><rect y="13.33" width="30" height="6.72" fill="#fff"/>',
        SUI: '<rect width="30" height="20" fill="#d52b1e"/><rect x="13" y="4" width="4" height="12" fill="#fff"/><rect x="9" y="8" width="12" height="4" fill="#fff"/>',
        SVK: '<rect y="0.00" width="30" height="6.72" fill="#fff"/><rect y="6.67" width="30" height="6.72" fill="#0b4ea2"/><rect y="13.33" width="30" height="6.72" fill="#ee1c25"/><path d="M7 5H14V11C14 14 10.5 15.5 10.5 15.5C10.5 15.5 7 14 7 11Z" fill="#ee1c25" stroke="#fff" stroke-width="0.8"/>',
        SVN: '<rect y="0.00" width="30" height="6.72" fill="#fff"/><rect y="6.67" width="30" height="6.72" fill="#005da4"/><rect y="13.33" width="30" height="6.72" fill="#ed1c24"/><path d="M6 4H12V9C12 11.5 9 12.5 9 12.5C9 12.5 6 11.5 6 9Z" fill="#005da4" stroke="#ed1c24" stroke-width="0.6"/>',
        SWE: '<rect width="30" height="20" fill="#006aa7"/><rect x="8" width="6" height="20" fill="#fecc02"/><rect y="7" width="30" height="6" fill="#fecc02"/>',
        TTO: '<rect width="30" height="20" fill="#ce1126"/><path d="M4 0H12L26 20H18Z" fill="#fff"/><path d="M6 0H10L24 20H20Z" fill="#000"/>',
        TUN: '<rect width="30" height="20" fill="#e70013"/><circle cx="15" cy="10" r="5" fill="#fff"/><circle cx="15" cy="10" r="3.2" fill="#e70013"/><circle cx="16" cy="10" r="2.6" fill="#fff"/><path d="M16.2 8.4L17.14 11.30L14.68 9.50H17.72L15.26 11.30Z" fill="#e70013"/>',
        TUR: '<rect width="30" height="20" fill="#e30a17"/><circle cx="12" cy="10" r="5" fill="#fff"/><circle cx="13.3" cy="10" r="4" fill="#e30a17"/><path d="M19 7.8L20.30 11.78L16.91 9.32H21.09L17.70 11.78Z" fill="#fff"/>',
        UKR: '<rect y="0.00" width="30" height="10.05" fill="#0057b7"/><rect y="10.00" width="30" height="10.05" fill="#ffd700"/>',
        URU: '<rect y="0.00" width="30" height="2.27" fill="#fff"/><rect y="2.22" width="30" height="2.27" fill="#0038a8"/><rect y="4.44" width="30" height="2.27" fill="#fff"/><rect y="6.67" width="30" height="2.27" fill="#0038a8"/><rect y="8.89" width="30" height="2.27" fill="#fff"/><rect y="11.11" width="30" height="2.27" fill="#0038a8"/><rect y="13.33" width="30" height="2.27" fill="#fff"/><rect y="15.56" width="30" height="2.27" fill="#0038a8"/><rect y="17.78" width="30" height="2.27" fill="#fff"/><rect width="11" height="11.1" fill="#fff"/><circle cx="5.5" cy="5.5" r="3" fill="#fcd116"/>',
        USA: '<rect y="0.00" width="30" height="1.59" fill="#b22234"/><rect y="1.54" width="30" height="1.59" fill="#fff"/><rect y="3.08" width="30" height="1.59" fill="#b22234"/><rect y="4.62" width="30" height="1.59" fill="#fff"/><rect y="6.15" width="30" height="1.59" fill="#b22234"/><rect y="7.69" width="30" height="1.59" fill="#fff"/><rect y="9.23" width="30" height="1.59" fill="#b22234"/><rect y="10.77" width="30" height="1.59" fill="#fff"/><rect y="12.31" width="30" height="1.59" fill="#b22234"/><rect y="13.85" width="30" height="1.59" fill="#fff"/><rect y="15.38" width="30" height="1.59" fill="#b22234"/><rect y="16.92" width="30" height="1.59" fill="#fff"/><rect y="18.46" width="30" height="1.59" fill="#b22234"/><rect width="13" height="10.8" fill="#3c3b6e"/>',
        UZB: '<rect y="0.00" width="30" height="6.72" fill="#0099b5"/><rect y="6.67" width="30" height="6.72" fill="#fff"/><rect y="13.33" width="30" height="6.72" fill="#1eb53a"/><rect y="6.3" width="30" height="0.6" fill="#ce1126"/><rect y="13.1" width="30" height="0.6" fill="#ce1126"/><circle cx="5" cy="3.3" r="2" fill="#fff"/><circle cx="5.8" cy="3.3" r="1.7" fill="#0099b5"/>',
        VEN: '<rect y="0.00" width="30" height="6.72" fill="#fcd116"/><rect y="6.67" width="30" height="6.72" fill="#00247d"/><rect y="13.33" width="30" height="6.72" fill="#cf142b"/>',
        WAL: '<rect y="0.00" width="30" height="10.05" fill="#fff"/><rect y="10.00" width="30" height="10.05" fill="#00b140"/><path d="M8 14C9 9 13 8 16 9L19 6L22 8L20 10C22 11 23 13 22 15L20 13L17 15L13 13L10 16Z" fill="#c8102e"/>',
        ZIM: '<rect y="0.00" width="30" height="2.91" fill="#319208"/><rect y="2.86" width="30" height="2.91" fill="#ffd200"/><rect y="5.71" width="30" height="2.91" fill="#de2010"/><rect y="8.57" width="30" height="2.91" fill="#000"/><rect y="11.43" width="30" height="2.91" fill="#de2010"/><rect y="14.29" width="30" height="2.91" fill="#ffd200"/><rect y="17.14" width="30" height="2.91" fill="#319208"/><path d="M0 0L13 10L0 20Z" fill="#fff" stroke="#000" stroke-width="0.5"/><path d="M5 7.5L6.47 12.03L2.62 9.22H7.38L3.53 12.03Z" fill="#de2010"/>',
    };
    const flag = code => svgEl(`<svg viewBox="0 0 30 20">${FLAGS[code] || '<rect width="30" height="20" fill="#666"/>'}</svg>`, 'flag');

    const shieldBadge = club => svgEl(
        `<svg viewBox="0 0 30 36"><path d="M15 1 L28 5 L28 17 C28 26 22 32 15 35 C8 32 2 26 2 17 L2 5 Z" fill="${col(club.c1, '#333')}" stroke="${col(club.c2, '#fff')}" stroke-width="2"/>` +
        `<text x="15" y="22" fill="${col(club.text, '#fff')}" text-anchor="middle" font-family="Anton, sans-serif" font-size="11">${esc(club.short)}</text></svg>`,
        'badge');
    // custom badge: Config.Clubs[x].badge, else html/img/badges/<clubKey>.png/.webp, else the drawn shield
    const badgeMissing = {};
    function badge(club) {
        const srcs = [];
        if (club.badge) srcs.push(club.badge);
        if (club.key) ['png', 'webp'].forEach(ext => srcs.push(`img/badges/${club.key}.${ext}`));
        const miss = club.badge || club.key;
        if (!srcs.length || badgeMissing[miss]) return shieldBadge(club);
        let i = 0;
        const img = h('img', { class: 'badge badge-img', src: srcs[0], draggable: 'false', alt: '' });
        img.onerror = () => {
            i++;
            if (i < srcs.length) { img.src = srcs[i]; return; }
            badgeMissing[miss] = true;
            img.replaceWith(shieldBadge(club));
        };
        return img;
    }

    /* ----- illustrated player (generic cartoon, not a likeness) ----- */
    const HAIR = {
        crop: h => `<path d="M66 80 C64 48 84 36 100 36 C118 36 137 48 134 80 C130 62 118 54 100 54 C84 54 71 62 66 80 Z" fill="${h}"/>`,
        buzz: h => `<path d="M68 72 C70 50 86 42 100 42 C116 42 131 50 132 72 C126 60 115 55 100 55 C86 55 74 60 68 72 Z" fill="${h}" opacity="0.9"/>`,
        curly: h => [[74, 62, 11], [86, 48, 12], [101, 42, 13], [116, 48, 12], [127, 62, 11], [93, 56, 10], [110, 56, 10]]
            .map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${h}"/>`).join(''),
        slick: h => `<path d="M65 82 C60 46 90 32 113 36 C134 40 140 60 135 82 C129 58 108 50 90 55 C77 59 69 69 65 82 Z" fill="${h}"/>`,
        bald: () => `<ellipse cx="90" cy="54" rx="12" ry="6" fill="#fff" opacity="0.18"/>`,
    };

    // photo lookup: config image, else html/img/players/<cardId>.png/.jpg/.webp, else Config.PhotoUrl, else silhouette/cartoon
    const PHOTO_EXT = ['png', 'jpg', 'webp'];
    const photoMissing = {};
    let photoUrl = '';
    function photoSources(id) {
        const list = PHOTO_EXT.map(ext => `img/players/${id}.${ext}`);
        if (photoUrl) list.push(photoUrl.split('{id}').join(encodeURIComponent(id)));
        return list;
    }
    function portrait(card) {
        if (card.image) {
            const im = h('img', { src: card.image, draggable: 'false' });
            im.onload = () => { const box = im.parentElement; if (box) box.classList.add('has-photo'); };
            return im;
        }
        if (card.id && !photoMissing[card.id]) {
            const wrap = h('div', { class: 'fc-photo' });
            const srcs = photoSources(card.id);
            let i = 0;
            const img = h('img', { draggable: 'false' });
            // a real photo fills the whole picture area of the card instead of the small cartoon box
            img.onload = () => { const box = wrap.parentElement; if (box) box.classList.add('has-photo'); };
            img.onerror = () => {
                i++;
                if (i < srcs.length) { img.src = srcs[i]; return; }
                photoMissing[card.id] = true;
                wrap.replaceWith(card.look ? cartoon(card) : silhouette(card));
            };
            img.src = srcs[0];
            wrap.appendChild(img);
            return wrap;
        }
        return card.look ? cartoon(card) : silhouette(card);
    }

    // no photo and no cartoon look: a plain player silhouette in the club colours
    function silhouette(card) {
        const c1 = col(card.club && card.club.c1, '#333');
        const c2 = col(card.club && card.club.c2, '#fff');
        const kit = card.kit ? `<text x="100" y="192" fill="${c2}" text-anchor="middle" font-family="Anton, sans-serif" font-size="30">${esc(card.kit)}</text>` : '';
        return svgEl(`<svg viewBox="0 0 200 200">
<path d="M16 200 C20 150 58 136 100 136 C142 136 180 150 184 200 Z" fill="${c1}" stroke="${c2}" stroke-width="2"/>
<path d="M84 137 L100 156 L116 137" fill="none" stroke="${c2}" stroke-width="5" stroke-linejoin="round"/>
${kit}
<rect x="88" y="104" width="24" height="34" rx="8" fill="#000" opacity="0.55"/>
<ellipse cx="100" cy="78" rx="32" ry="40" fill="#000" opacity="0.55"/>
</svg>`);
    }

    function cartoon(card) {
        const lk = card.look || {};
        const c1 = col(card.club && card.club.c1, '#333');
        const c2 = col(card.club && card.club.c2, '#fff');
        const skin = col(lk.skin, '#e8b58f');
        const hair = col(lk.hair, '#3a2a1a');
        const style = HAIR[lk.style] ? lk.style : 'crop';
        const fx = (card.rarity && card.rarity.effects) || {};
        const kit = card.kit ? `<text x="140" y="186" fill="${c2}" font-family="Anton, sans-serif" font-size="22">${esc(card.kit)}</text>` : '';
        const armband = fx.armband ? `<g transform="rotate(-18 165 158)"><rect x="150" y="150" width="30" height="16" rx="3" fill="#ffd400"/><text x="165" y="163" fill="#111" text-anchor="middle" font-family="Anton, sans-serif" font-size="13">C</text></g>` : '';
        const beard = lk.beard ? `<path d="M68 88 C70 114 86 125 100 125 C114 125 130 114 132 88 C126 106 113 111 100 111 C87 111 74 106 68 88 Z" fill="${hair}" opacity="0.92"/>` : '';
        return svgEl(`<svg viewBox="0 0 200 200">
<path d="M10 200 C14 148 56 132 100 132 C144 132 186 148 190 200 Z" fill="${c1}" stroke="${c2}" stroke-width="2"/>
<path d="M10 200 C12 168 26 150 46 142 L54 200 Z" fill="${c2}"/>
<path d="M190 200 C188 168 174 150 154 142 L146 200 Z" fill="${c2}"/>
<path d="M84 134 L100 158 L116 134" fill="none" stroke="${c2}" stroke-width="6" stroke-linejoin="round"/>
${kit}${armband}
<rect x="87" y="106" width="26" height="34" rx="8" fill="${skin}"/>
<rect x="87" y="116" width="26" height="12" rx="6" fill="#000" opacity="0.14"/>
<ellipse cx="67" cy="86" rx="6" ry="10" fill="${skin}"/>
<ellipse cx="133" cy="86" rx="6" ry="10" fill="${skin}"/>
<ellipse cx="100" cy="82" rx="33" ry="41" fill="${skin}"/>
<path d="M100 41 C118 41 133 58 133 82 C133 106 118 123 100 123 C112 110 116 96 116 82 C116 62 110 48 100 41 Z" fill="#000" opacity="0.08"/>
${HAIR[style](hair)}${beard}
<path d="M82 74 L94 73" fill="none" stroke="${hair}" stroke-width="3" stroke-linecap="round"/>
<path d="M106 73 L118 74" fill="none" stroke="${hair}" stroke-width="3" stroke-linecap="round"/>
<ellipse cx="89" cy="83" rx="3.2" ry="3.6" fill="#1b1b1b"/>
<ellipse cx="111" cy="83" rx="3.2" ry="3.6" fill="#1b1b1b"/>
<path d="M100 86 L96 97 L102 98" fill="none" stroke="#000" stroke-width="2" opacity="0.22" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M90 105 Q100 112 110 105" fill="none" stroke="#5a2d22" stroke-width="2.5" stroke-linecap="round"/>
</svg>`);
    }

    // long surnames shrink to fit the name plate instead of being cut off
    const lastSize = t => { const n = String(t).length; return n > 9 ? { 'font-size': `${Math.max(16, Math.round(30 * 9 / n))}px` } : null; };

    /* ----- card face ----- */
    // misprints change what gets printed
    const MISSPELL = s => { if (!s || s.length < 4) return s + 'e'; const i = 1 + (s.length % (s.length - 2)); return s.slice(0, i) + s[i + 1] + s[i] + s.slice(i + 2); };
    function applyError(card) {
        const e = card.error && card.error.id;
        if (!e) return card;
        const c = Object.assign({}, card);
        if (e === 'misspelt') c.last = MISSPELL(card.last || '');
        if (e === 'noStats') { c.att = ''; c.def = ''; }
        if (e === 'wrongFlag') c.nation = ({ ENG: 'SCO', SCO: 'ENG', FRA: 'ITA', ESP: 'POR', POR: 'ESP', BRA: 'ARG', ARG: 'BRA', NED: 'GER', GER: 'NED' })[card.nation] || 'ENG';
        return c;
    }

    // handwritten signature of the (pun) name
    function signature(card) {
        const name = `${(card.first || '').trim()} ${(card.last || '').trim()}`.trim() || card.label || '';
        const seed = [...name].reduce((a, ch) => (a * 31 + ch.charCodeAt(0)) % 9973, 7);
        const rot = -8 - (seed % 9);
        return svgEl(`<svg viewBox="0 0 300 110"><g transform="rotate(${rot} 150 55)">
            <text x="150" y="68" text-anchor="middle" font-family="'Mrs Saint Delafield','Allura','Brush Script MT',cursive" font-size="${Math.max(38, 64 - name.length * 1.6)}" fill="#1b2fa8" stroke="#1b2fa8" stroke-width="0.6" opacity=".92">${esc(name)}</text>
            <path d="M${60 + seed % 30} 84 Q150 ${96 + seed % 8} ${240 - seed % 25} 78" fill="none" stroke="#1b2fa8" stroke-width="2.2" stroke-linecap="round" opacity=".85"/></g></svg>`, 'fc-sig');
    }

    function insertLayers(card) {
        const ins = card.insert;
        if (!ins) return [];
        const club = card.club || {};
        const out = [];
        if (ins.id === 'relic' || ins.id === 'autorelic') {
            out.push(h('div', { class: 'fc-relic', style: { '--rc1': col(club.c1, '#c00'), '--rc2': col(club.c2, '#fff') } },
                h('div', { class: 'fc-relic-win' }), h('div', { class: 'fc-relic-txt' }, 'MATCH-WORN MATERIAL')));
        }
        if (ins.id === 'auto' || ins.id === 'autorelic') {
            out.push(h('div', { class: 'fc-auto' }, signature(card)), h('div', { class: 'fc-auto-stamp' }, 'AUTHENTIC AUTOGRAPH'));
        }
        if (ins.caseHit) {
            out.push(h('div', { class: 'fc-case' }, h('div', { class: 'fc-case-frame' }), h('div', { class: 'fc-case-shine' }),
                h('div', { class: 'fc-case-banner' }, h('span', null, 'LEGENDS'), h('small', null, 'OF THE GAME'))));
        }
        out.push(h('div', { class: 'fc-ins-num' + (ins.caseHit ? ' case' : '') }, h('b', null, ins.label.toUpperCase()), h('span', null, `${String(ins.print || 0).padStart(2, '0')}/${ins.max}`)));
        return out;
    }

    // creatures / Los Santos cards (from the card creator). Football keeps its own face above.
    function themedFace(card) {
        const t = card.rarity || {}, club = card.club || {};
        const fx = t.effects || {};
        const sl = card.statLabels || { att: 'ATK', def: 'DEF' };
        const glitter = fx.glitter || (card.foil ? '#ffffff' : null);
        const layers = [];
        if (fx.holo || card.foil) layers.push(h('div', { class: 'fx fx-holo' }));
        if (fx.dark) layers.push(h('div', { class: 'fx fx-legend' }));
        if (glitter) layers.push(h('div', { class: 'fx fx-glit' }), h('div', { class: 'fx fx-glit b' }));
        if (fx.sweep) layers.push(h('div', { class: 'fx fx-sweep' }));
        if (fx.follow || card.foil) layers.push(h('div', { class: 'fx fx-follow' }));
        const art = card.image ? h('img', { src: card.image, draggable: 'false' }) : h('div', { class: 'tc-empty' });
        const name = card.label || ((card.first || '') + ' ' + (card.last || '')).trim();
        const tag = card.theme === 'creatures'
            ? [h('span', { class: 'tc-chip' }, club.label || card.element || ''), card.stage ? h('span', { class: 'tc-chip alt' }, String(card.stage).replace(/^stage(\d)$/, 'Stage $1').replace(/^./, c => c.toUpperCase())) : null]
            : [h('span', { class: 'tc-chip' }, card.category ? String(card.category).toUpperCase() : 'CARD'), h('span', { class: 'tc-chip alt' }, card.district || club.label || '')];
        return h('div', {
            class: ['fc', 'tc', 'tc-' + card.theme, t.id, fx.dark && 'dark', fx.glow && 'glow', card.foil && 'foil', fx.pulse && 'pulse'].filter(Boolean).join(' '),
            style: {
                '--frame': t.frame || '#f4f4f4', '--pulse': col(fx.pulse, '#ffffff'), '--c1': col(club.c1, '#333'), '--c2': col(club.c2, '#fff'),
                '--plate': t.plate || '#fff', '--plate-text': t.plateText || '#121212', '--glit': col(glitter, '#ffffff'), '--sweep': fx.sweep || 'transparent', '--speed': fx.speed || '4.5s',
            },
        },
            h('div', { class: 'fc-in' },
                h('div', { class: 'tc-art' }, art), h('div', { class: 'tc-vig' }), layers,
                h('div', { class: 'tc-top' }, h('div', { class: 'tc-name', style: name.length > 10 ? { 'font-size': `${Math.max(14, Math.round(24 * 10 / name.length))}px` } : null }, name), h('div', { class: 'tc-gem' }, (t.label || '').toUpperCase())),
                h('div', { class: 'tc-tags' }, tag),
                card.hp ? h('div', { class: 'tc-hp' }, h('small', null, 'HP'), String(card.hp)) : null,
                h('div', { class: 'tc-foot' },
                    (card.move || card.blurb) ? h('div', { class: 'tc-blurb' }, card.move ? h('b', null, card.move) : null, card.blurb ? h('span', null, card.blurb) : null) : null,
                    h('div', { class: 'tc-stats' },
                        h('div', { class: 'tc-stat att' }, h('b', null, String(card.att ?? '')), h('small', null, sl.att)),
                        h('div', { class: 'tc-mid' }, h('div', { class: 'print' }, printText(card) || (card.footer || '')), h('div', { class: 'serial' }, card.serial || '')),
                        h('div', { class: 'tc-stat def' }, h('b', null, String(card.def ?? '')), h('small', null, sl.def)))),
            ),
        );
    }

    function cardFace(card) {
        if (card.theme && card.theme !== 'football') return themedFace(card);
        card = applyError(card);
        const t = card.rarity || {};
        const par = card.parallel || null;
        // a numbered parallel adds its own frame and effects on top of the card type's
        const fx = Object.assign({}, t.effects || {}, par ? par.effects || {} : {});
        const club = card.club || {};
        const glitter = fx.glitter || (card.foil ? '#ffffff' : null);
        const classes = ['fc', t.id, fx.dark && 'dark', fx.glow && 'glow', card.foil && 'foil', par && 'par', par && ('par-' + par.id), fx.pulse && 'pulse',
            card.insert && 'ins', card.insert && ('ins-' + card.insert.id), card.error && ('err-' + card.error.id)].filter(Boolean).join(' ');
        const att = String(card.att ?? ''), def = String(card.def ?? '');

        const layers = [];
        if (fx.holo || card.foil) layers.push(h('div', { class: 'fx fx-holo' }));
        if (fx.dark) layers.push(h('div', { class: 'fx fx-legend' }));
        if (glitter) layers.push(h('div', { class: 'fx fx-glit' }), h('div', { class: 'fx fx-glit b' }));
        if (fx.sweep) layers.push(h('div', { class: 'fx fx-sweep' }));
        if (fx.follow || card.foil) layers.push(h('div', { class: 'fx fx-follow' }));

        return h('div', {
            class: classes,
            style: {
                '--frame': (par && par.frame) || t.frame || '#f4f4f4',
                '--pulse': col(fx.pulse, '#ffffff'),
                '--c1': col(club.c1, '#333'), '--c2': col(club.c2, '#fff'),
                '--plate': t.plate || '#fff', '--plate-text': t.plateText || '#121212', '--pos-bg': t.posBg || '#121212',
                '--glit': col(glitter, '#ffffff'), '--sweep': fx.sweep || 'transparent', '--speed': fx.speed || '4.5s',
            },
        },
            h('div', { class: 'fc-in' },
                h('div', { class: 'fc-bg' }),
                h('div', { class: 'fc-streaks' }),
                h('div', { class: 'fc-swoosh' }),
                h('div', { class: 'fc-portrait' }, portrait(card)),
                layers,
                insertLayers(card),
                card.rookie ? h('div', { class: 'fc-rc' }, svgEl('<svg viewBox="0 0 40 44"><path d="M20 1 L38 7 L38 22 C38 33 30 40 20 43 C10 40 2 33 2 22 L2 7 Z" fill="#fff" stroke="#111" stroke-width="2.5"/><text x="20" y="29" text-anchor="middle" font-family="Anton, sans-serif" font-size="17" fill="#d4001a">RC</text></svg>')) : null,
                h('div', { class: 'fc-top' },
                    badge(club),
                    h('div', { class: 'club' },
                        h('b', null, club.label || ''),
                        h('span', null, (t.label || '').toUpperCase(), card.foil ? h('span', { class: 'foil-tag' }, 'FOIL') : null),
                    ),
                    h('div', { class: 'code' }, card.code || ''),
                ),
                par ? h('div', { class: 'fc-par', style: { '--stamp': col(par.stamp, '#333') } },
                    h('b', null, (par.label || '').toUpperCase()),
                    h('span', null, par.max === 1 ? '1/1' : `${String(par.print || 0).padStart(2, '0')}/${par.max}`),
                ) : null,
                h('div', { class: 'fc-plate-bg' }),
                h('div', { class: 'fc-plate' },
                    card.pos ? h('div', { class: 'pos' }, card.pos) : null,
                    h('div', { class: 'names' },
                        h('div', { class: 'first' }, card.first || ''),
                        h('div', { class: 'last', style: lastSize(card.last || card.label || '') }, card.last || card.label || ''),
                    ),
                ),
                h('div', { class: 'fc-stats' },
                    h('div', { class: 'fc-stat att' }, h('div', { class: 'num' + (att.length > 2 ? ' small' : '') }, att), h('div', { class: 'lbl' }, 'ATTACK')),
                    h('div', { class: 'fc-mid' },
                        card.nation ? flag(card.nation) : null,
                        h('div', { class: 'print' }, printText(card) || (card.footer || '')),
                        h('div', { class: 'serial' }, card.serial || ''),
                    ),
                    h('div', { class: 'fc-stat def' }, h('div', { class: 'num' + (def.length > 2 ? ' small' : '') }, def), h('div', { class: 'lbl' }, 'DEFENCE')),
                ),
            ),
        );
    }

    // card face with its condition overlay (dirt, scratches, crease...) on top
    function condFace(card) {
        const face = cardFace(card);
        if (!card.cond || !card.cond.c || !window.CondFX) return face;
        // off-centre print: the picture sits closer to one edge, so the borders are uneven
        const off = window.CondFX.centering && window.CondFX.centering(card.cond.c);
        if (off && face.classList && face.classList.contains('fc')) {
            const b = 6, p = v => `${Math.max(0.5, b + v).toFixed(1)}px`;
            face.style.padding = `${p(off.dy)} ${p(-off.dx)} ${p(-off.dy)} ${p(off.dx)}`;
        }
        const host = h('div', { class: 'cfx-host' }, face);
        host.appendChild(window.CondFX.create(card.cond.c).el);
        return host;
    }

    function slabFace(card) {
        const g = card.graded;
        const sub = [card.club && card.club.label, card.rarity && card.rarity.label, card.parallel ? `${card.parallel.label} ${card.parallel.max === 1 ? '1/1' : (card.parallel.print || 0) + '/' + card.parallel.max}` : null, card.foil ? 'Foil' : null, printText(card)].filter(Boolean).join(' · ');
        return h('div', { class: 'slab' + (g.sub ? ' has-subs' : '') },
            h('div', { class: 'slab-label' + (g.sub ? ' has-subs' : '') + (g.pristine ? ' pristine' : '') + (g.skin ? ' skin-' + g.skin.id : ''), style: g.skin && g.skin.id !== 'standard' && !g.pristine ? { background: g.skin.bg, color: g.skin.fg } : null },
                h('div', { class: 'l-info' },
                    h('div', { class: 'l-brand' }, g.brand || 'GRADED'),
                    h('div', { class: 'l-name' }, card.label || ''),
                    h('div', { class: 'l-sub' }, sub),
                    h('div', { class: 'l-sub' }, `${card.serial || ''}${g.cert ? '  ·  Cert ' + g.cert : ''}`),
                ),
                h('div', { class: 'l-grade' },
                    h('div', { class: 'g-word' }, g.label || ''),
                    h('div', { class: 'g-num' }, String(g.grade)),
                ),
                g.sub ? h('div', { class: 'l-subs' },
                    [['CENTERING', g.sub.cen], ['CORNERS', g.sub.cor], ['EDGES', g.sub.edg], ['SURFACE', g.sub.sur]].map(([k, v]) => h('div', null, k, h('b', null, String(v)))),
                ) : null,
            ),
            condFace(card),
        );
    }

    let backImage = null;

    // big pulls: autographs, relics, 1/1s, error cards
    function isBigHit(c) { return !!(c.insert || c.error || (c.parallel && c.parallel.max <= 10)); }
    function celebrate(c) {
        const title = c.insert ? c.insert.label.toUpperCase() : c.error ? 'ERROR CARD!' : c.parallel.max === 1 ? `${c.parallel.label.toUpperCase()} 1 OF 1` : `${c.parallel.label.toUpperCase()} /${c.parallel.max}`;
        const sub = c.insert ? `${String(c.insert.print || 0).padStart(2, '0')}/${c.insert.max}  ·  ${c.label || ''}` : (c.label || '');
        const el = h('div', { class: 'bighit' + (c.insert && c.insert.caseHit ? ' casehit' : '') }, h('div', { class: 'bh-flash' }), h('div', { class: 'bh-rays' }),
            h('div', { class: 'bh-text' }, h('div', { class: 'bh-kicker' }, c.insert && c.insert.caseHit ? 'CASE HIT' : 'BIG HIT'), h('div', { class: 'bh-title' }, title), h('div', { class: 'bh-sub' }, sub)));
        for (let i = 0; i < 70; i++) {
            const p = h('i', { class: 'bh-spark', style: { left: `${50 + (Math.random() - 0.5) * 20}%`, '--dx': `${(Math.random() - 0.5) * 1400}px`, '--dy': `${-200 - Math.random() * 600}px`, '--r': `${Math.random() * 720}deg`, 'animation-delay': `${Math.random() * 0.25}s`, background: ['#f7d774', '#fff', '#ff6ad5', '#6ad0ff', '#6affc1'][i % 5] } });
            el.appendChild(p);
        }
        document.body.appendChild(el);
        setTimeout(() => sfx(sfxCfg.rare), 120); setTimeout(() => sfx(sfxCfg.rare), 700);
        setTimeout(() => el.classList.add('out'), 2600);
        setTimeout(() => el.remove(), 3300);
    }

    let backs = {};

  /* ---- card back from a creator spec {style,c1,c2,accent,emblem,title,sub} ---- */
  function backSvg(s) {
    const esc = t => String(t || '').replace(/[&<>"]/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m]));
    const pv = s.image || '';
    const bgImg = pv ? `<image href="${esc(pv)}" x="0" y="0" width="288" height="408" preserveAspectRatio="${s.fit === 'stretch' ? 'none' : ({ top: 'xMinYMin', bottom: 'xMaxYMax' }[s.position] || 'xMidYMid') + (s.fit === 'contain' ? ' meet' : ' slice')}"/>` : '';
    if (pv && s.imageOnly) return `<svg viewBox="0 0 288 408" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">${bgImg}</svg>`;
    const bgDim = pv ? `<rect width="288" height="408" fill="#000" opacity="${Math.min(.8, Math.max(0, parseFloat(s.dim) || 0))}"/>` : '';
    const c1 = s.c1 || '#0e1a2e', c2 = s.c2 || '#1c3358', ac = s.accent || '#f7d774', gid = 'bg' + esc(s.id || 'x');
    let pat = '';
    if (s.style === 'stripes') for (let i = -8; i < 20; i++) pat += `<rect x="${i * 28}" y="-20" width="12" height="460" fill="${ac}" opacity=".10" transform="rotate(18 144 204)"/>`;
    else if (s.style === 'diamonds') for (let y = 0; y < 9; y++) for (let x = 0; x < 6; x++) pat += `<path d="M${x * 56 + 28} ${y * 52 + 6} l20 20 -20 20 -20 -20z" fill="none" stroke="${ac}" stroke-width="1.5" opacity=".18"/>`;
    else if (s.style === 'rings') for (let i = 1; i < 8; i++) pat += `<circle cx="144" cy="204" r="${i * 26}" fill="none" stroke="${ac}" stroke-width="1.5" opacity=".16"/>`;
    const emb = s.emblem ? `<path d="M144 118 L190 132 L190 174 C190 204 170 224 144 236 C118 224 98 204 98 174 L98 132Z" fill="${c1}" stroke="${ac}" stroke-width="3"/><text x="144" y="190" fill="${ac}" text-anchor="middle" font-family="Anton, Inter, sans-serif" font-size="${String(s.emblem).length > 3 ? 24 : 32}">${esc(s.emblem).toUpperCase()}</text>` : '';
    return `<svg viewBox="0 0 288 408" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="${gid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${c2}"/><stop offset="1" stop-color="${c1}"/></linearGradient></defs><rect width="288" height="408" fill="url(#${gid})"/>${bgImg}${bgDim}${pat}<rect x="12" y="12" width="264" height="384" rx="6" fill="none" stroke="${ac}" stroke-width="2"/><rect x="20" y="20" width="248" height="368" rx="3" fill="none" stroke="${ac}" stroke-width=".8" opacity=".6"/>${emb}<text x="144" y="290" fill="${s.titleColour || ac}" text-anchor="middle" font-family="Anton, Inter, sans-serif" font-size="26" letter-spacing="3">${esc(s.title).toUpperCase()}</text><text x="144" y="316" fill="${s.subColour || '#ffffff'}" opacity=".85" text-anchor="middle" font-family="Inter, sans-serif" font-size="12" font-weight="700" letter-spacing="4">${esc(s.sub).toUpperCase()}</text></svg>`;
  }


    function cardBack(card) {
        if (card && card.error && card.error.id === 'blankBack') return h('div', { class: 'cb cb-blank' });
        const bs = backs[(card && card.theme) || 'football'] || backs.football;
        if (bs && !(card && card.error && card.error.id === 'blankBack')) {
            return h('div', { class: 'cb' }, h('div', { class: 'cb-in cb-gen' }, svgEl(backSvg(bs), 'cbgen')));
        }
        if (card && card.error && card.error.id === 'blankBack') return h('div', { class: 'cb cb-blank' });
        if (backImage) {
            return h('div', { class: 'cb' }, h('div', { class: 'cb-in cb-img' }, h('img', { src: backImage, draggable: 'false' })));
        }
        return h('div', { class: 'cb' },
            h('div', { class: 'cb-in' },
                svgEl('<svg viewBox="0 0 288 408" preserveAspectRatio="none"><rect x="14" y="14" width="260" height="380" rx="4" fill="none" stroke="#f7d774" stroke-width="2"/><circle cx="144" cy="204" r="70" fill="none" stroke="#f7d774" stroke-width="2"/><line x1="14" y1="204" x2="274" y2="204" stroke="#f7d774" stroke-width="2"/><rect x="74" y="14" width="140" height="56" fill="none" stroke="#f7d774" stroke-width="2"/><rect x="74" y="338" width="140" height="56" fill="none" stroke="#f7d774" stroke-width="2"/></svg>', 'pitch'),
                svgEl('<svg viewBox="0 0 60 72" style="width:96px;height:115px;position:relative"><path d="M30 2 L57 10 L57 34 C57 52 45 64 30 70 C15 64 3 52 3 34 L3 10 Z" fill="#0e1a2e" stroke="#f7d774" stroke-width="3"/><text x="30" y="42" fill="#f7d774" text-anchor="middle" font-family="Anton, sans-serif" font-size="20">UKC</text></svg>'),
                h('div', { class: 'cb-title' }, 'FOOTBALL CARDS'),
                h('div', { class: 'cb-sub' }, 'SERIES 1'),
            ),
        );
    }

    function attachTilt(slot, tilt) {
        slot.addEventListener('mousemove', e => {
            const rect = slot.getBoundingClientRect();
            const x = Math.min(Math.max((e.clientX - rect.left) / rect.width, 0), 1);
            const y = Math.min(Math.max((e.clientY - rect.top) / rect.height, 0), 1);
            tilt.classList.add('active');
            tilt.style.setProperty('--rx', `${(0.5 - y) * 18}deg`);
            tilt.style.setProperty('--ry', `${(x - 0.5) * 22}deg`);
            tilt.style.setProperty('--mx', `${100 - x * 100}%`);
            tilt.style.setProperty('--my', `${100 - y * 100}%`);
            tilt.style.setProperty('--lx', `${x * 100}%`);
            tilt.style.setProperty('--ly', `${y * 100}%`);
        });
        slot.addEventListener('mouseleave', () => {
            tilt.classList.remove('active');
            ['--rx', '--ry'].forEach(p => tilt.style.setProperty(p, '0deg'));
        });
    }

    /**
     * opts: { scale, flipped, tilt, onFlip }
     */
    function renderCard(card, opts = {}) {
        const { scale = 1, flipped = true, tilt = true, onFlip = null } = opts;
        const slabbed = !!card.graded;
        const t = card.rarity || {};

        const tiltEl = h('div', { class: 'tilt' }, slabbed ? slabFace(card) : cardFace(card));
        const flip = h('div', { class: 'flip' + (flipped ? ' flipped' : '') },
            h('div', { class: 'face' }, tiltEl),
            h('div', { class: 'back' }, cardBack()),
        );
        const slot = h('div', {
            class: 'slot' + (slabbed ? ' slabbed' : '') + (flipped ? ' revealed' : '') + (isHigh(card) ? ' r-high' : ''),
            style: { '--s': String(scale), '--glow': t.glow || '#ffffff' },
        },
            h('div', { class: 'burst' }),
            h('div', { class: 'scale' }, flip),
        );

        if (!flipped) {
            flip.addEventListener('click', () => {
                if (flip.classList.contains('flipped')) return;
                flip.classList.add('flipped');
                slot.classList.add('revealed');
                if (onFlip) onFlip(card, slot);
            });
        }
        if (tilt) attachTilt(slot, tiltEl);
        slot._flip = () => flip.click();
        slot._isFlipped = () => flip.classList.contains('flipped');
        return slot;
    }

    /* ----- 3D graded slab: drag to turn it round, scroll to zoom, double-click to reset ----- */
    const SLAB_W = 330, SLAB_H = 560, SLAB_D = 18, SLAB_LAYERS = 10;

    function slabBackFace(card) {
        const g = card.graded || {};
        const bars = [];
        const seed = String(g.cert || card.serial || '0');
        for (let i = 0; i < 46; i++) {
            const c = seed.charCodeAt(i % seed.length) + i * 7;
            bars.push(h('i', { style: { width: `${1 + (c % 3)}px`, 'margin-right': `${1 + ((c >> 2) % 2)}px` } }));
        }
        return h('div', { class: 'slab slab-back' },
            h('div', { class: 'slab-label sb-label' },
                h('div', { class: 'sb-left' },
                    h('div', { class: 'l-brand' }, g.brand || 'GRADED'),
                    h('div', { class: 'sb-cert' }, `CERT #${g.cert || '--------'}`),
                    h('div', { class: 'sb-bars' }, bars),
                ),
                h('div', { class: 'sb-holo' }, h('span', null, g.brand ? g.brand.split(' ')[0] : 'OK')),
            ),
            h('div', { class: 'sb-card' }, cardBack()),
        );
    }

    // generic turnable 3D object: a front, a back and a stack of rims for its thickness
    function obj3d(o) {
        const { w, h, d, layers, cls, frontEl, backEl, scale } = o;
        const front = h_('div', { class: 's3d-face s3d-front', style: { transform: `translateZ(${d / 2}px)` } }, h_('div', { class: 'tilt active s3d-fx' }, frontEl), h_('div', { class: 's3d-glare' }));
        const back = h_('div', { class: 's3d-face s3d-back', style: { transform: `rotateY(180deg) translateZ(${d / 2}px)` } }, backEl, h_('div', { class: 's3d-glare' }));
        const rims = [];
        for (let i = 1; i < layers; i++) {
            const z = -d / 2 + (d * i) / layers;
            rims.push(h_('div', { class: 's3d-layer', style: { transform: `translateZ(${z.toFixed(2)}px)` } }));
        }
        const obj = h_('div', { class: 's3d-obj' }, rims, back, front, o.extra || []);
        const shadow = h_('div', { class: 's3d-shadow' });
        const stage = h_('div', { class: 's3d-stage ' + (cls || ''), style: { width: `${w * scale}px`, height: `${h * scale}px` } },
            h_('div', { class: 's3d-scale', style: { width: `${w}px`, height: `${h}px`, transform: `scale(${scale})` } }, shadow, obj));
        return { stage, obj, front, shadow };
    }
    const h_ = (...a) => h(...a);

    function slab3d(card, scale) {
        return turnable(obj3d({ w: SLAB_W, h: SLAB_H, d: SLAB_D, layers: SLAB_LAYERS, cls: 's3d-slab', frontEl: slabFace(card), backEl: slabBackFace(card), scale }));
    }

    // penny sleeve / toploader planes around a raw card
    function protPlanes(prot, d) {
        if (!prot) return [];
        const out = [];
        const plane = (cls, z, back) => out.push(h('div', { class: 'prot ' + cls, style: { transform: `${back ? 'rotateY(180deg) ' : ''}translateZ(${z}px)` } }));
        plane('prot-sleeve', d / 2 + 1.5, false); plane('prot-sleeve', d / 2 + 1.5, true);
        if (prot === 'toploader') {
            plane('prot-top', d / 2 + 7, false); plane('prot-top', d / 2 + 7, true);
            for (let i = 0; i < 6; i++) out.push(h('div', { class: 'prot prot-rim', style: { transform: `translateZ(${(-d / 2 - 7 + (d + 14) * i / 5).toFixed(1)}px)` } }));
        }
        return out;
    }

    function card3d(card, scale) {
        const prot = card.cond && card.cond.prot;
        return turnable(obj3d({ w: 300, h: 420, d: 3, layers: 3, cls: 's3d-card' + (prot ? ' has-prot' : ''), frontEl: condFace(card), backEl: cardBack(card), scale, extra: protPlanes(prot, 3) }));
    }

    function turnable(parts) {
        const { stage, obj, front, shadow } = parts;
        const fxEl = front.firstChild;

        let rx = 0, ry = 0, zoom = 1, vx = 0, vy = 0, drag = null, lastMove = 0, raf = 0, t0 = performance.now(), home = null;
        const apply = now => {
            let sx = 0, sy = 0;
            // gentle idle sway once it has been left alone for a bit
            if (!drag && !home && now - lastMove > 1800) {
                const k = Math.min(1, (now - lastMove - 1800) / 1200);
                sx = Math.sin((now - t0) / 1700) * 4 * k;
                sy = Math.sin((now - t0) / 2300) * 7 * k;
            }
            const ax = rx + sx, ay = ry + sy;
            obj.style.transform = `scale(${zoom}) rotateX(${ax.toFixed(2)}deg) rotateY(${ay.toFixed(2)}deg)`;
            // light: glare slides across the plastic as it turns, the card's holo follows too
            const ny = ((ay % 360) + 540) % 360 - 180; // -180..180
            const gx = 50 - (ny / 60) * 50, gy = 50 + (ax / 60) * 50;
            stage.style.setProperty('--gx', `${gx.toFixed(1)}%`);
            stage.style.setProperty('--gy', `${gy.toFixed(1)}%`);
            fxEl.style.setProperty('--mx', `${Math.max(0, Math.min(100, gx))}%`);
            fxEl.style.setProperty('--my', `${Math.max(0, Math.min(100, gy))}%`);
            fxEl.style.setProperty('--lx', `${Math.max(0, Math.min(100, 100 - gx))}%`);
            fxEl.style.setProperty('--ly', `${Math.max(0, Math.min(100, 100 - gy))}%`);
            const turn = Math.abs(Math.cos(ay * Math.PI / 180));
            shadow.style.transform = `translateX(-50%) scale(${(0.35 + 0.65 * turn) * zoom}, ${zoom})`;
        };
        const tick = now => {
            if (!stage.isConnected) { cancelAnimationFrame(raf); return; }
            if (!drag) {
                if (home) { // ease back to the nearest front / back
                    rx += (0 - rx) * 0.14; ry += (home.ry - ry) * 0.14;
                    if (Math.abs(rx) < 0.05 && Math.abs(ry - home.ry) < 0.05) { rx = 0; ry = home.ry; home = null; lastMove = now; }
                } else if (Math.abs(vx) > 0.01 || Math.abs(vy) > 0.01) { // throw inertia
                    ry += vy; rx = Math.max(-65, Math.min(65, rx + vx));
                    vx *= 0.93; vy *= 0.93; lastMove = now;
                }
            }
            apply(now);
            raf = requestAnimationFrame(tick);
        };
        stage.addEventListener('pointerdown', e => {
            if (e.button !== 0) return;
            drag = { x: e.clientX, y: e.clientY, t: performance.now() };
            vx = vy = 0; home = null;
            stage.setPointerCapture(e.pointerId);
            stage.classList.add('grabbing');
        });
        stage.addEventListener('pointermove', e => {
            if (!drag) return;
            const now = performance.now();
            const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
            const dt = Math.max(8, now - drag.t);
            ry += dx * 0.45; rx = Math.max(-65, Math.min(65, rx - dy * 0.35));
            vy = (dx * 0.45) * (16 / dt); vx = (-dy * 0.35) * (16 / dt);
            drag = { x: e.clientX, y: e.clientY, t: now };
            lastMove = now;
        });
        const endDrag = () => { if (!drag) return; if (performance.now() - drag.t > 80) { vx = vy = 0; } drag = null; stage.classList.remove('grabbing'); };
        stage.addEventListener('pointerup', endDrag);
        stage.addEventListener('pointercancel', endDrag);
        stage.addEventListener('wheel', e => {
            e.preventDefault();
            zoom = Math.max(0.7, Math.min(1.6, zoom * (e.deltaY > 0 ? 0.92 : 1.08)));
            lastMove = performance.now();
        }, { passive: false });
        const snap = extra => { vx = vy = 0; home = { ry: Math.round((ry + (extra || 0)) / 180) * 180 }; };
        stage.addEventListener('dblclick', () => { zoom = 1; home = { ry: Math.round(ry / 360) * 360 }; });
        stage._flip = () => snap(180);
        stage._reset = () => { zoom = 1; home = { ry: Math.round(ry / 360) * 360 }; };
        raf = requestAnimationFrame(tick);
        return stage;
    }

    /* ---------------------------------------------------------------- views */
    function clear() {
        cleanStop();
        root.innerHTML = '';
        mode = null;
    }

    function close() {
        const was = mode;
        clear();
        if (was) post('close');
    }

    function fitScale(count, perRowMax, cardH) {
        const perRow = Math.min(count, perRowMax);
        const rows = Math.ceil(count / perRowMax);
        const sw = (window.innerWidth - 160 - 16 * perRow) / (300 * perRow);
        const sh = (window.innerHeight - 260 - 16 * rows) / (cardH * rows);
        return Math.max(0.4, Math.min(1, sw, sh));
    }

    /* ----- pack opening ----- */
    /* ----- 3D pack: drag along the top to peel the strip off ----- */
    const PK_W = 260, PK_H = 400, STRIP_H = 58;

    // paper-tear noise made on the fly (no sound file needed)
    const tearAudio = {
        ctx: null, src: null, gain: null,
        start() {
            if (!sfxCfg.enabled) return;
            try {
                const AC = window.AudioContext || window.webkitAudioContext;
                if (!AC) return;
                if (!this.ctx) this.ctx = new AC();
                const ctx = this.ctx;
                const len = ctx.sampleRate * 1.5;
                const buf = ctx.createBuffer(1, len, ctx.sampleRate);
                const d = buf.getChannelData(0);
                let last = 0;
                for (let i = 0; i < len; i++) { // crackly noise: random clicks over soft noise
                    const white = Math.random() * 2 - 1;
                    last = 0.6 * last + 0.4 * white;
                    d[i] = (Math.random() < 0.02 ? white * 1.6 : last * 0.5);
                }
                this.src = ctx.createBufferSource();
                this.src.buffer = buf; this.src.loop = true;
                const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 2600; bp.Q.value = 0.8;
                const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 900;
                this.gain = ctx.createGain(); this.gain.gain.value = 0;
                this.src.connect(bp).connect(hp).connect(this.gain).connect(ctx.destination);
                this.src.start();
            } catch (e) { this.src = null; }
        },
        level(speed) {
            if (!this.gain) return;
            const vol = Math.max(0, Math.min(1, Number(sfxCfg.volume) || 0.5));
            this.gain.gain.setTargetAtTime(Math.min(1, speed * 7) * vol * 0.5, this.ctx.currentTime, 0.04);
        },
        stop() {
            if (!this.src) return;
            try { this.gain.gain.setTargetAtTime(0, this.ctx.currentTime, 0.05); this.src.stop(this.ctx.currentTime + 0.3); } catch (e) {}
            this.src = null; this.gain = null;
        },
    };

    function jaggedPoints(w, h, step) {
        const pts = [];
        for (let x = 0; x <= w; x += step) pts.push(`${x},${(Math.random() * h * 0.8 + h * 0.1).toFixed(1)}`);
        return pts;
    }

    function buildPack(data, count) {
        const art = data.art || backImage || null;
        const artImg = top => art ? h('img', { class: 'pk-art', src: art, draggable: 'false', style: { top: `${top}px` } }) : null;

        // body
        const front = h('div', { class: 'pk-face front' },
            artImg(-STRIP_H),
            !art ? h('div', { class: 'pk-fallback' }, h('b', null, 'FOOTBALL CARDS'), h('span', null, data.label || '')) : null,
            h('div', { class: 'pk-foil' }),
            h('div', { class: 'pk-shine' }),
            h('div', { class: 'pk-crimp bottom' }),
            h('div', { class: 'pk-mouth' }),
        );
        const back = h('div', { class: 'pk-face back' },
            h('div', { class: 'pk-backinfo' },
                h('b', null, (data.label || 'BOOSTER').toUpperCase()),
                h('span', null, `${count} CARDS PER PACK`),
                h('span', { class: 'bars' }),
            ),
            h('div', { class: 'pk-foil' }),
            h('div', { class: 'pk-crimp bottom' }),
        );
        // torn edge left on the pack (random every time)
        const edgePts = jaggedPoints(PK_W, 8, 3.25);
        const edge = svgEl(`<svg viewBox="0 0 ${PK_W} 8" preserveAspectRatio="none"><polygon points="0,8 ${edgePts.join(' ')} ${PK_W},8" fill="#f4f1ea"/></svg>`, 'pk-edge');
        const glow = h('div', { class: 'pk-glow' });
        const body = h('div', { class: 'pk-body' }, front, back, h('div', { class: 'pk-side l' }), h('div', { class: 'pk-side r' }), edge, glow);

        // strip = one piece, drawn twice: the torn-off part (flap) and the part still attached (rest)
        const stripEdge = jaggedPoints(PK_W, 6, 3.25).join(' ');
        const stripLayer = cls => h('div', { class: 'pk-strip-part ' + cls },
            h('div', { class: 'pk-strip-f' },
                art ? h('img', { class: 'pk-art', src: art, draggable: 'false', style: { top: '0px' } }) : h('div', { class: 'pk-fallback-strip' }),
                h('div', { class: 'pk-foil' }),
                h('div', { class: 'pk-crimp top' }),
            ),
            h('div', { class: 'pk-strip-b' }),
            svgEl(`<svg viewBox="0 0 ${PK_W} 6" preserveAspectRatio="none"><polygon points="0,0 ${PK_W},0 ${stripEdge}" fill="#f4f1ea"/></svg>`, 'pk-strip-edge'),
        );
        const flap = stripLayer('flap');
        const rest = stripLayer('rest');
        const strip = h('div', { class: 'pk-strip' }, rest, flap);

        const cardsOut = h('div', { class: 'pk-cards' }, [0, 1, 2].map(i => h('div', { class: 'pk-card', style: { '--i': String(i) } }, backImage ? h('img', { src: backImage, draggable: 'false' }) : null)));
        const pk = h('div', { class: 'pk' }, cardsOut, body, strip);
        const flakes = h('div', { class: 'pk-flakes' });
        const guide = h('div', { class: 'pk-guide' }, h('div', { class: 'pk-hand' }));
        const scene = h('div', { class: 'pk-scene' }, pk, flakes, guide);
        return { scene, pk, strip, flap, rest, edge, glow, flakes, guide };
    }

    function openPack(data) {
        clear();
        mode = 'pack';
        const cards = data.cards || [];
        const P = buildPack(data, cards.length);
        const { scene, pk, strip, flap, rest, edge, glow, guide } = P;

        const hint = h('div', { class: 'hint pk-hint' }, 'Grab the top of the pack and drag across to rip it open');
        const stage = h('div', { class: 'pack-stage' }, scene, hint);
        const overlay = h('div', { class: 'overlay' },
            h('div', { class: 'overlay-title' }, 'Opening ', h('b', null, data.label || '')),
            stage,
        );
        root.appendChild(overlay);

        // state
        let dragging = false, done = false, flying = false;
        let dir = 1, startX = 0;            // tear direction and where it started (0..1)
        let target = 0, cur = 0, lastCur = 0;
        let tiltX = 0, tiltY = -12, tTiltX = 0, tTiltY = -12;
        let lift = 0, tLift = 0, liftBias = 0, raf = 0;

        const pos = e => {
            const r = pk.getBoundingClientRect();
            return { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height };
        };

        function frame(t) {
            if (mode !== 'pack' || !scene.isConnected) { tearAudio.stop(); return; }
            // ease the tear toward the pointer - this is what makes it smooth
            cur += (target - cur) * (done ? 0.28 : 0.22);
            if (Math.abs(target - cur) < 0.0005) cur = target;
            const speed = Math.max(0, cur - lastCur);
            lastCur = cur;

            tearAudio.level(dragging || done ? speed : 0);

            // one-piece tear: the torn part hinges at the tear point and lifts toward your hand
            const front = dir > 0 ? startX + (1 - startX) * cur : startX - startX * cur;
            if (!flying) {
                const fx = front * PK_W;
                const tornPx = dir > 0 ? fx - startX * PK_W : startX * PK_W - fx;
                tLift = Math.min(38, 4 + tornPx * 0.16 + liftBias);
                lift += (tLift - lift) * 0.18;
                const shown = cur > 0.001 || dragging;
                flap.style.visibility = shown ? 'visible' : 'hidden';
                if (dir > 0) {
                    flap.style.clipPath = `inset(0 ${((1 - front) * 100).toFixed(2)}% 0 0)`;
                    rest.style.clipPath = `inset(0 0 0 ${(front * 100).toFixed(2)}%)`;
                } else {
                    flap.style.clipPath = `inset(0 0 0 ${(front * 100).toFixed(2)}%)`;
                    rest.style.clipPath = `inset(0 ${((1 - front) * 100).toFixed(2)}% 0 0)`;
                }
                flap.style.transformOrigin = `${fx.toFixed(1)}px 58px`;
                const l = shown ? lift : 0;
                flap.style.transform = `translateZ(${(l * 0.35).toFixed(2)}px) rotateZ(${(dir * l).toFixed(2)}deg) rotateX(${(-l * 0.35).toFixed(2)}deg)`;
                flap.style.filter = `brightness(${(1 + l / 140).toFixed(3)})`;
            }

            // torn edge on the pack grows with the tear
            const a = Math.max(0, Math.min(1, dir > 0 ? startX : 1 - startX));
            const covered = Math.min(1, a + (1 - a) * cur);
            edge.style.clipPath = dir > 0
                ? `inset(0 ${((1 - covered) * 100).toFixed(2)}% 0 ${(Math.max(0, startX - 0.02) * 100).toFixed(2)}%)`
                : `inset(0 ${(Math.max(0, 1 - startX - 0.02) * 100).toFixed(2)}% 0 ${((1 - covered) * 100).toFixed(2)}%)`;

            // pack eases toward the pointer
            tiltX += (tTiltX - tiltX) * 0.12;
            tiltY += (tTiltY - tiltY) * 0.12;
            pk.style.transform = `rotateX(${tiltX.toFixed(2)}deg) rotateY(${tiltY.toFixed(2)}deg)`;

            if (done && !flying && cur > 0.995) flyOff();
            raf = requestAnimationFrame(frame);
        }
        raf = requestAnimationFrame(frame);

        scene.addEventListener('pointermove', e => {
            if (flying) return;
            const r = scene.getBoundingClientRect();
            const nx = (e.clientX - r.left) / r.width - 0.5;
            const ny = (e.clientY - r.top) / r.height - 0.5;
            tTiltY = nx * (dragging ? 12 : 34);
            tTiltX = -ny * (dragging ? 6 : 16);
            if (!dragging) return;
            const p = pos(e);
            liftBias = Math.max(0, Math.min(18, ((STRIP_H / PK_H) - p.y) * PK_H * 0.35)); // pull upward = lifts more
            const prog = dir > 0 ? (p.x - startX) / (1 - startX || 1) : (startX - p.x) / (startX || 1);
            target = Math.max(target, Math.min(1, prog)); // never un-tears
            if (target >= 0.86) finishTear();
        });

        scene.addEventListener('pointerdown', e => {
            if (done || flying) return;
            const p = pos(e);
            if (p.y < -0.05 || p.y > 0.28 || p.x < -0.1 || p.x > 1.1) return; // grab the top
            if (target === 0) {             // first grab decides the direction
                dir = p.x > 0.5 ? -1 : 1;
                startX = dir > 0 ? Math.max(0, Math.min(p.x, 0.35)) : Math.min(1, Math.max(p.x, 0.65));
            }
            dragging = true;
            scene.setPointerCapture && scene.setPointerCapture(e.pointerId);
            pk.classList.add('tearing');
            guide.classList.add('hide');
            tearAudio.start();
        });

        const release = () => {
            if (!dragging) return;
            dragging = false;
            pk.classList.remove('tearing');
            if (!done) tearAudio.stop();
        };
        scene.addEventListener('pointerup', release);
        scene.addEventListener('pointercancel', release);

        function finishTear() {
            if (done) return;
            done = true;
            dragging = false;
            target = 1;
        }

        function flyOff() {
            flying = true;
            tearAudio.stop();
            sfx(sfxCfg.rip);
            post('ripped');
            // the whole strip is now the flap: it comes free and drops away
            rest.style.visibility = 'hidden';
            flap.style.clipPath = 'none';
            flap.style.transition = 'transform .9s cubic-bezier(.35,.1,.6,1), opacity .9s ease-in';
            void flap.offsetWidth;
            flap.style.transform = `translate(${-dir * 170}px, 150px) translateZ(30px) rotateZ(${dir * 95}deg) rotateX(-30deg)`;
            flap.style.opacity = '0';
            pk.classList.remove('tearing');
            pk.classList.add('ripped');
            glow.classList.add('on');
            hint.textContent = '';
            setTimeout(() => pk.classList.add('cards-out'), 450);
            setTimeout(() => { cancelAnimationFrame(raf); sfx(sfxCfg.deal); showCards(); }, 1450);
        }

        function showCards() {
            if (mode !== 'pack') return;
            stage.remove();
            const scale = fitScale(cards.length, 5, 420);
            let revealed = 0;
            const doneBtn = h('button', { class: 'btn primary', onclick: close }, 'Done');
            const revealBtn = h('button', { class: 'btn' }, 'Reveal all');
            const perRow = Math.min(cards.length, 5);
            const grid = h('div', { class: 'card-grid', style: { 'max-width': `${perRow * (300 * scale + 16) + 40}px` } });

            const slots = cards.map((card, i) => {
                const slot = renderCard(card, {
                    scale, flipped: false,
                    onFlip: c => {
                        revealed++;
                        if (data.token) post('packTake', { token: data.token, index: i + 1 });   // into the inventory now
                        sfx(sfxCfg.flip);
                        if (isRare(c)) setTimeout(() => sfx(sfxCfg.rare), 250);
                        if (isBigHit(c)) celebrate(c);
                        if (revealed >= cards.length) revealBtn.disabled = true;
                    },
                });
                slot.style.animationDelay = `${i * 90}ms`;
                grid.appendChild(slot);
                return slot;
            });

            revealBtn.addEventListener('click', () => {
                revealBtn.disabled = true;
                let delay = 0;
                slots.forEach(sl => {
                    if (!sl._isFlipped()) {
                        setTimeout(() => { if (mode === 'pack') sl._flip(); }, delay);
                        delay += 380;
                    }
                });
            });

            overlay.appendChild(grid);
            overlay.appendChild(h('div', { class: 'btn-row' }, revealBtn, doneBtn));
            overlay.appendChild(h('div', { class: 'hint' }, data.token ? 'Click a card to flip it into your inventory · Done gives you the rest' : 'Click a card to flip it · cards are already in your inventory'));
        }
    }

    /* ----- view own card ----- */
    function viewCard(data) {
        clear();
        mode = 'view';
        const card = data.card;
        const cardH = card.graded ? 560 : 420;
        const scale = Math.max(0.6, Math.min(1.35, (window.innerHeight - 220) / cardH));

        const info = [card.club && card.club.label, card.rarity && card.rarity.label, card.parallel ? `${card.parallel.label} ${card.parallel.max === 1 ? '1 of 1' : (card.parallel.print || 0) + '/' + card.parallel.max}` : null, card.foil ? 'Foil' : null, printText(card), card.serial]
            .filter(Boolean).join('  ·  ');

        const buttons = [];
        if (data.canShow) {
            const showBtn = h('button', { class: 'btn primary' }, 'Show nearby');
            showBtn.addEventListener('click', () => {
                post('show', { slot: data.slot });
                showBtn.disabled = true;
                setTimeout(() => { showBtn.disabled = false; }, 5000);
            });
            buttons.push(showBtn);
        }
        if (data.slot && data.v2) {
            if (data.v2.hand) buttons.push(h('button', { class: 'btn', onclick: () => { post('handHold', { slot: data.slot }); close(); } }, 'Hold in hand'));
            if (data.v2.gift) buttons.push(h('button', { class: 'btn', onclick: () => { post('giftOpen', { slot: data.slot, serial: card.serial }); } }, 'Send as a gift'));
        }
        buttons.push(h('button', { class: 'btn', onclick: close }, 'Close'));

        let shown;
        shown = card.graded ? slab3d(card, scale) : card3d(card, scale);
        buttons.unshift(h('button', { class: 'btn', onclick: () => shown._flip() }, 'Turn over'));
        if (card.graded && data.slot) {
            let armed = false;
            const crackBtn = h('button', { class: 'btn' }, 'Crack slab');
            crackBtn.addEventListener('click', () => {
                if (!armed) { armed = true; crackBtn.textContent = 'Sure? Click again'; setTimeout(() => { armed = false; crackBtn.textContent = 'Crack slab'; }, 3000); return; }
                post('crack', { slot: data.slot, serial: card.serial });
            });
            buttons.unshift(crackBtn);
        }

        // condition + protection (raw cards)
        const tools = data.tools || {};
        const cond = card.cond && card.cond.scores ? card.cond : null;
        let condLine = null;
        if (cond) {
            const prot = cond.prot === 'toploader' ? 'In a toploader' : cond.prot === 'sleeve' ? 'In a penny sleeve' : 'Loose';
            condLine = h('div', { class: 'cond-line' },
                h('b', null, tools.loupe ? `${cond.scores.word} (${cond.scores.overall})` : cond.glance), `  ·  ${prot}`);
            const act = action => post('protect', { slot: data.slot, serial: card.serial, action }).then(res => {
                if (res && res.card) viewCard(Object.assign({}, data, { card: res.card, tools: res.tools }));
            });
            const pb = [];
            if (data.slot) {
                if (!cond.prot && tools.sleeve) pb.push(h('button', { class: 'btn', onclick: () => act('sleeve') }, 'Put in sleeve'));
                if (cond.prot === 'sleeve' && tools.toploader) pb.push(h('button', { class: 'btn', onclick: () => act('toploader') }, 'Put in toploader'));
                if (cond.prot) pb.push(h('button', { class: 'btn', onclick: () => act('remove') }, cond.prot === 'toploader' ? 'Take out of toploader' : 'Take out of sleeve'));
            }
            if (tools.loupe) pb.push(h('button', { class: 'btn primary', onclick: () => inspectCard(card, () => viewCard(data)) }, 'Inspect'));
            buttons.unshift(...pb);
        }

        root.appendChild(h('div', { class: 'overlay' },
            shown,
            h('div', { class: 'hint s3d-hint' }, 'Drag to turn  ·  Scroll to zoom  ·  Double-click to reset'),
            condLine,
            h('div', { class: 'hint' }, info),
            h('div', { class: 'btn-row' }, buttons),
        ));
    }

    /* ----- appraisal letter ----- */
    function appraisal(a) {
        clear();
        mode = 'letter';
        const money = n => '£' + Math.floor(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        root.appendChild(h('div', { class: 'overlay' },
            h('div', { class: 'letter' },
                h('div', { class: 'lt-head' }, h('div', { class: 'lt-logo' }, '★'), h('div', null, h('div', { class: 'lt-org' }, a.issuer || 'LS Card Exchange Appraisals'), h('div', { class: 'lt-sub' }, 'Certificate of appraisal'))),
                h('div', { class: 'lt-ref' }, `Ref ${a.ref || '-'}  ·  ${a.date || ''}`),
                h('p', null, 'This is to certify that the trading card described below has been examined and appraised.'),
                h('table', { class: 'lt-table' },
                    h('tr', null, h('td', null, 'Card'), h('td', null, a.title || '')),
                    h('tr', null, h('td', null, 'Serial number'), h('td', null, a.serial || '-')),
                    h('tr', null, h('td', null, a.graded ? 'Grade' : 'Condition'), h('td', null, a.condition || '-')),
                    h('tr', null, h('td', null, 'Presented by'), h('td', null, a.holder || '-')),
                    h('tr', { class: 'lt-val' }, h('td', null, 'Appraised value'), h('td', null, money(a.value))),
                ),
                h('p', { class: 'lt-small' }, 'Value at the date of appraisal, based on the LS Card Exchange market. Card prices change over time. Check the serial number on the card matches this letter.'),
                h('div', { class: 'lt-sign' }, h('div', { class: 'lt-sig' }, 'R. Hollis'), h('div', null, 'Senior Appraiser')),
            ),
            h('div', { class: 'btn-row' },
                a.ref ? h('button', { class: 'btn', onclick: e => { e.target.disabled = true; post('appraisalSave', { ref: a.ref }); } }, 'Save to phone') : null,
                a.ref ? h('button', { class: 'btn', onclick: e => { e.target.disabled = true; post('appraisalSaveComputer', { ref: a.ref }); } }, 'Save to computer') : null,
                h('button', { class: 'btn primary', onclick: close }, 'Close')),
        ));
    }

    /* ----- Admin panel (/cardadmin) ----- */
    let adm = null;
    const aMoney = n => (n < 0 ? '-£' : '£') + Math.abs(Math.floor(Number(n) || 0)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const aTime = t => { const d = new Date(t * 1000); return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ' ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); };
    function aCall(name, data) {
        return post('admin', { name, data: data || {} }).then(r => {
            if (!r || !r.ok) { aToast((r && r.error) || 'No answer from the server.', true); return null; }
            return r.data;
        });
    }
    function aToast(msg, bad) {
        const t = h('div', { class: 'adm-toast' + (bad ? ' bad' : '') }, msg);
        root.appendChild(t);
        setTimeout(() => t.remove(), 3200);
    }
    const FLAG_INFO = {
        auctions: ['Pause auctions', 'No new listings, bids, buy it now or offers. Live auctions keep their timers.'],
        sellBack: ['Stop the shop buying cards', 'The card shop buyer won’t buy cards or sealed product.'],
        shop: ['Close the card shop', 'No packs, supplies or repacks can be bought from the shop.'],
        market: ['Freeze market prices', 'Prices stop moving until you turn this off.'],
        series2: ['Series 2 live (ON = on sale)', 'Turn ON to put Series 2 packs on sale. Needs at least one Series 2 card in the custom folder. OFF hides them again.'],
    };
    function admin(d) {
        clear();
        mode = 'admin';
        adm = { tab: 'overview', overview: d.overview || {}, me: d.me, give: { kind: 'card', target: d.me, foil: false, grade: '', pristine: false, count: 1 }, logs: { kind: '', search: '', page: 1 } };
        renderAdmin();
    }
    function renderAdmin() {
        if (mode !== 'admin' || !adm) return;
        root.innerHTML = '';
        const tabs = [['overview', 'Overview'], ['give', 'Players & give'], ['flags', 'Switches'], ['auctions', 'Auctions'], ['pool', 'Repack pool'], ['logs', 'Money logs']];
        const body = h('div', { class: 'adm-body' }, h('div', { class: 'adm-loading' }, 'Loading...'));
        const panel = h('div', { class: 'adm' },
            h('div', { class: 'adm-head' }, h('div', { class: 'adm-title' }, 'Trading Cards · Staff'),
                h('button', { class: 'adm-x', onclick: close, title: 'Close' }, '✕')),
            h('div', { class: 'adm-tabs' }, tabs.map(([id, label]) => h('button', { class: adm.tab === id ? 'on' : '', onclick: () => { adm.tab = id; renderAdmin(); } }, label))),
            body);
        root.appendChild(h('div', { class: 'overlay adm-wrap' }, panel));
        const fill = el => { body.innerHTML = ''; body.appendChild(el); };
        ADM[adm.tab](fill);
    }
    const ADM = {
        overview(fill) {
            aCall('overview').then(o => {
                if (!o) return;
                adm.overview = o;
                const labels = o.labels || {};
                const kinds = Object.keys(labels).filter(k => k !== 'admin');
                const row = (k) => {
                    const a = (o.day || {})[k] || {}, b = (o.week || {})[k] || {};
                    return h('tr', null, h('td', null, labels[k]), h('td', { class: 'num' }, String(a.n || 0)), h('td', { class: 'num ' + ((a.total || 0) < 0 ? 'neg' : 'pos') }, aMoney(a.total || 0)),
                        h('td', { class: 'num' }, String(b.n || 0)), h('td', { class: 'num ' + ((b.total || 0) < 0 ? 'neg' : 'pos') }, aMoney(b.total || 0)));
                };
                const tile = (v, l, cls) => h('div', { class: 'adm-tile ' + (cls || '') }, h('b', null, v), h('span', null, l));
                const paused = Object.entries(o.flags || {}).filter(([k, v]) => v && k !== 'series2').map(([k]) => FLAG_INFO[k] ? FLAG_INFO[k][0] : k);
                fill(h('div', null,
                    paused.length ? h('div', { class: 'adm-warn' }, 'Switched on: ' + paused.join(' · ')) : null,
                    h('div', { class: 'adm-tiles' },
                        tile(String(o.online || 0), 'Players online'),
                        tile(o.shopOpen ? 'Open' : 'Closed', 'Card shop · ' + (o.hours || ''), o.shopOpen ? 'ok' : 'bad'),
                        tile(String(o.live || 0), 'Live auctions · ' + aMoney(o.liveBids || 0) + ' bid'),
                        tile(String(o.pool || 0), 'Repack pool · ' + aMoney(o.poolValue || 0)),
                        tile(String(o.payouts || 0), 'Unclaimed payouts · ' + aMoney(o.payoutsTotal || 0)),
                        tile(String(o.undelivered || 0), 'Parcels waiting to send')),
                    h('h3', null, 'Money moved (from the player’s side: + paid to them, - paid by them)'),
                    h('table', { class: 'adm-table' },
                        h('tr', null, h('th', null, 'Type'), h('th', null, '24h #'), h('th', null, '24h total'), h('th', null, '7d #'), h('th', null, '7d total')),
                        kinds.map(row)),
                    h('div', { class: 'adm-row' },
                        h('button', { class: 'btn', onclick: e => { e.target.disabled = true; aCall('report').then(r => { e.target.disabled = false; if (r) aToast('Market report posted to Discord.'); }); } }, 'Post market report to Discord now')),
                ));
            });
        },
        give(fill) {
            const g = adm.give;
            Promise.all([aCall('players'), adm.options ? Promise.resolve(adm.options) : aCall('options')]).then(([players, options]) => {
                if (!players || !options) return;
                adm.options = options;
                const pl = h('div', { class: 'adm-players' }, players.map(p => h('div', { class: 'adm-pl' + (Number(g.target) === p.id ? ' on' : ''), onclick: () => { g.target = p.id; renderAdmin(); } },
                    h('b', null, `[${p.id}] ${p.name || '?'}`), h('span', null, p.identifier || ''))));
                const info = h('div', { class: 'adm-info' }, 'Loading player...');
                if (g.target) aCall('player', { id: g.target }).then(p => {
                    info.innerHTML = '';
                    if (!p) return;
                    const st = p.stats || {};
                    info.appendChild(h('div', null,
                        h('h3', null, `${p.name} (${p.identifier})`),
                        h('div', { class: 'adm-tiles small' },
                            h('div', { class: 'adm-tile' }, h('b', null, String(p.cards)), h('span', null, 'cards held')),
                            h('div', { class: 'adm-tile' }, h('b', null, aMoney(p.value)), h('span', null, 'cards worth')),
                            h('div', { class: 'adm-tile' }, h('b', null, aMoney(p.sealed)), h('span', null, 'sealed worth')),
                            h('div', { class: 'adm-tile' }, h('b', null, String(st.packs || 0)), h('span', null, 'packs opened'))),
                        (p.top || []).filter(Boolean).length ? h('div', { class: 'adm-small' }, 'Best cards: ' + p.top.filter(Boolean).map(c => `${c.title} (${aMoney(c.value)})`).join(' · ')) : null,
                        h('h3', null, 'Recent money'),
                        (p.logs || []).length ? h('table', { class: 'adm-table' }, p.logs.map(l => h('tr', null, h('td', null, aTime(l.at)), h('td', null, ((adm.overview || {}).labels || {})[l.kind] || l.kind), h('td', { class: 'num ' + (l.amount < 0 ? 'neg' : 'pos') }, aMoney(l.amount)), h('td', null, l.detail || ''))))
                            : h('div', { class: 'adm-small' }, 'Nothing logged yet.')));
                });
                const kindSeg = h('div', { class: 'adm-seg' }, [['card', 'A card'], ['pack', 'Packs / boxes']].map(([k, l]) => h('button', { class: g.kind === k ? 'on' : '', onclick: () => { g.kind = k; renderAdmin(); } }, l)));
                let form;
                if (g.kind === 'pack') {
                    const sel = h('select', { class: 'adm-in', onchange: e => { g.pack = e.target.value; } }, options.packs.map(p => { const o = h('option', { value: p.id }, p.label); if (g.pack === p.id) o.selected = true; return o; }));
                    if (!g.pack && options.packs[0]) g.pack = options.packs[0].id;
                    const cnt = h('input', { class: 'adm-in num', type: 'number', min: '1', max: '50', value: String(g.count), oninput: e => { g.count = e.target.value; } });
                    form = h('div', { class: 'adm-form' }, h('label', null, 'Product', sel), h('label', null, 'How many', cnt),
                        h('button', { class: 'btn primary', onclick: e => { e.target.disabled = true; aCall('give', { target: g.target, kind: 'pack', id: g.pack, count: g.count }).then(r => { e.target.disabled = false; if (r) aToast('Given.'); }); } }, 'Give'));
                } else {
                    const results = h('div', { class: 'adm-results' });
                    const drawResults = list => {
                        results.innerHTML = '';
                        (list || []).forEach(c => results.appendChild(h('div', { class: 'adm-res' + (g.card === c.id ? ' on' : ''), onclick: () => { g.card = c.id; g.cardName = c.name; drawResults(list); } },
                            h('b', null, c.name), h('span', null, `#${c.code} · ${c.type || ''}`))));
                    };
                    let tmr;
                    const q = h('input', { class: 'adm-in', placeholder: 'Search player name or card number...', value: g.q || '', oninput: e => { g.q = e.target.value; clearTimeout(tmr); tmr = setTimeout(() => aCall('searchCards', { q: g.q }).then(drawResults), 250); } });
                    if (g.q) aCall('searchCards', { q: g.q }).then(drawResults);
                    const ver = h('select', { class: 'adm-in', onchange: e => { g.version = e.target.value; } }, h('option', { value: '' }, 'Base card'),
                        options.parallels.map(p => { const o = h('option', { value: p.id }, p.label); if (g.version === p.id) o.selected = true; return o; }));
                    const grade = h('select', { class: 'adm-in', onchange: e => { g.grade = e.target.value; renderAdmin(); } }, h('option', { value: '' }, 'Raw (not graded)'),
                        [10, 9, 8, 7, 6, 5, 4, 3, 2, 1].map(n => { const o = h('option', { value: String(n) }, 'Graded ' + n); if (String(g.grade) === String(n)) o.selected = true; return o; }));
                    const chk = (label, key) => h('label', { class: 'adm-chk' }, (() => { const c = h('input', { type: 'checkbox', onchange: e => { g[key] = e.target.checked; } }); c.checked = !!g[key]; return c; })(), label);
                    form = h('div', { class: 'adm-form' }, q, results,
                        h('div', { class: 'adm-row' }, h('label', null, 'Version', ver), h('label', null, 'Grade', grade)),
                        h('div', { class: 'adm-row' }, chk('Foil', 'foil'), String(g.grade) === '10' ? chk('Pristine 10', 'pristine') : null),
                        h('button', { class: 'btn primary', onclick: e => {
                            if (!g.card) return aToast('Pick a card first.', true);
                            e.target.disabled = true;
                            aCall('give', { target: g.target, kind: 'card', id: g.card, version: g.version || '', foil: !!g.foil, grade: g.grade || null, pristine: !!g.pristine }).then(r => { e.target.disabled = false; if (r) aToast('Given: ' + (r.title || g.cardName)); });
                        } }, 'Give card'));
                }
                fill(h('div', { class: 'adm-split' },
                    h('div', { class: 'adm-col' }, h('h3', null, 'Online players'), pl),
                    h('div', { class: 'adm-col wide' }, info, h('h3', null, 'Give to this player'), kindSeg, form)));
            });
        },
        flags(fill) {
            aCall('overview').then(o => {
                if (!o) return;
                const flags = o.flags || {};
                fill(h('div', null, h('div', { class: 'adm-small' }, 'Switches stay as you leave them, even after a restart.'),
                    Object.keys(FLAG_INFO).map(k => {
                        const on = !!flags[k];
                        return h('div', { class: 'adm-flag' + (on ? ' on' : '') },
                            h('div', null, h('b', null, FLAG_INFO[k][0]), h('span', null, FLAG_INFO[k][1])),
                            h('button', { class: 'adm-toggle' + (on ? ' on' : ''), onclick: () => aCall('flag', { key: k, value: !on }).then(r => { if (r) renderAdmin(); }) }, h('i')));
                    })));
            });
        },
        auctions(fill) {
            aCall('auctions').then(r => {
                if (!r) return;
                if (!r.list.length) return fill(h('div', { class: 'adm-small' }, 'No live auctions.'));
                fill(h('table', { class: 'adm-table' },
                    h('tr', null, h('th', null, '#'), h('th', null, 'Item'), h('th', null, 'Seller'), h('th', null, 'Top bid'), h('th', null, 'Ends'), h('th', null, '')),
                    r.list.map(a => h('tr', null, h('td', null, String(a.id)), h('td', null, a.title), h('td', null, a.seller || ''),
                        h('td', { class: 'num' }, a.bid ? `${aMoney(a.bid)} (${a.bidder || '?'}, ${a.bids} bids)` : 'No bids · starts ' + aMoney(a.start)),
                        h('td', null, Math.max(0, Math.round((a.endsAt - r.now) / 60)) + 'm'),
                        h('td', null, h('button', { class: 'btn small danger', onclick: e => {
                            if (e.target.dataset.sure !== '1') { e.target.dataset.sure = '1'; e.target.textContent = 'Sure? Click again'; return; }
                            aCall('auctionCancel', { id: a.id }).then(x => { if (x) { aToast('Removed. Bids refunded, item sent back to the seller.'); renderAdmin(); } });
                        } }, 'Remove'))))));
            });
        },
        pool(fill) {
            aCall('pool').then(r => {
                if (!r) return;
                fill(h('div', null, h('div', { class: 'adm-small' }, `${r.total} cards in the pool (cards sold to the shop). Most valuable first.`),
                    h('table', { class: 'adm-table' }, r.list.map(c => h('tr', null, h('td', null, c.title), h('td', null, c.serial || ''), h('td', { class: 'num' }, aMoney(c.value)),
                        h('td', null, h('button', { class: 'btn small', onclick: () => aCall('poolRemove', { id: c.id }).then(x => { if (x) renderAdmin(); }) }, 'Take out')))))));
            });
        },
        logs(fill) {
            const L = adm.logs;
            aCall('logs', L).then(r => {
                if (!r) return;
                const labels = r.labels || {};
                const kind = h('select', { class: 'adm-in', onchange: e => { L.kind = e.target.value; L.page = 1; renderAdmin(); } }, h('option', { value: '' }, 'All types'),
                    Object.keys(labels).map(k => { const o = h('option', { value: k }, labels[k]); if (L.kind === k) o.selected = true; return o; }));
                const search = h('input', { class: 'adm-in', placeholder: 'Name, citizen ID or detail (Enter)', value: L.search, onkeydown: e => { if (e.key === 'Enter') { L.search = e.target.value; L.page = 1; renderAdmin(); } } });
                fill(h('div', null, h('div', { class: 'adm-row' }, kind, search),
                    r.list.length ? h('table', { class: 'adm-table' },
                        h('tr', null, h('th', null, 'When'), h('th', null, 'Player'), h('th', null, 'Type'), h('th', null, 'Amount'), h('th', null, 'Detail')),
                        r.list.map(l => h('tr', null, h('td', null, aTime(l.at)), h('td', null, (l.name || '?') + ' ', h('span', { class: 'adm-dim' }, l.identifier || '')), h('td', null, labels[l.kind] || l.kind),
                            h('td', { class: 'num ' + (l.amount < 0 ? 'neg' : 'pos') }, aMoney(l.amount)), h('td', null, l.detail || ''))))
                        : h('div', { class: 'adm-small' }, 'Nothing found.'),
                    h('div', { class: 'adm-row' },
                        h('button', { class: 'btn small', disabled: L.page <= 1 ? 'disabled' : null, onclick: () => { L.page--; renderAdmin(); } }, '‹ Newer'),
                        h('span', { class: 'adm-dim' }, 'Page ' + r.page),
                        h('button', { class: 'btn small', disabled: r.list.length < 50 ? 'disabled' : null, onclick: () => { L.page++; renderAdmin(); } }, 'Older ›'))));
            });
        },
    };

    /* ----- Top Trumps ----- */
    let tt = null;
    function ttMoney(n) { return '£' + Math.floor(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
    function ttScale() { return Math.max(0.5, Math.min(0.95, (window.innerHeight - 330) / 440)); }
    function ttStart(d) {
        clear();
        mode = 'tt';
        tt = { opponent: d.opponent, rounds: d.rounds, pot: d.pot, bet: d.bet, score: { you: 0, them: 0 }, round: 0, phase: 'deal' };
        ttRender();
    }
    function ttRound(d) {
        if (!tt) return;
        Object.assign(tt, { round: d.round, rounds: d.rounds, card: d.card, chooser: d.chooser, score: d.score, pot: d.pot, opponent: d.opponent || tt.opponent,
            deadline: Date.now() + (d.seconds || 20) * 1000, phase: 'choose', result: null, sent: false });
        ttRender();
        sfx(sfxCfg.deal);
    }
    function ttResult(d) {
        if (!tt) return;
        Object.assign(tt, { phase: 'result', result: d, score: d.score, card: d.you });
        ttRender();
        sfx(sfxCfg.flip);
        if (d.outcome === 'win') setTimeout(() => sfx(sfxCfg.rare), 450);
    }
    function ttEnd(d) {
        if (!tt) return;
        Object.assign(tt, { phase: 'end', end: d, score: d.score });
        ttRender();
        if (d.outcome === 'win') setTimeout(() => sfx(sfxCfg.rare), 200);
    }
    function ttChoose(stat) {
        if (!tt || tt.phase !== 'choose' || !tt.chooser || tt.sent) return;
        tt.sent = true;
        post('ttChoose', { stat });
        ttRender();
    }
    function ttStatLine(c, stat, value, cls) {
        const label = stat === 'att' ? 'ATTACK' : 'DEFENCE';
        return h('div', { class: 'tt-stat ' + (cls || '') }, h('span', null, label), h('b', null, String(value)), c && c.boost ? h('i', null, `+${c.boost}`) : null);
    }
    function ttRender() {
        if (!tt) return;
        root.innerHTML = '';
        const sc = ttScale();
        const score = tt.score || { you: 0, them: 0 };
        const head = h('div', { class: 'tt-head' },
            h('div', { class: 'tt-logo' }, 'TOP TRUMPS'),
            h('div', { class: 'tt-score' }, h('span', null, 'YOU'), h('b', null, `${score.you} – ${score.them}`), h('span', null, (tt.opponent || '').toUpperCase())),
            h('div', { class: 'tt-meta' }, tt.round ? `ROUND ${tt.round} / ${tt.rounds}` : 'DEALING…', tt.pot ? `  ·  POT ${ttMoney(tt.pot)}` : '  ·  NO BET'),
        );

        const back = () => { const el = renderCard({ rarity: {} }, { scale: sc, flipped: false, tilt: false }); el.style.pointerEvents = 'none'; return el; };
        let mine, theirs, mid, controls;
        const r = tt.result;
        if (tt.phase === 'deal' || !tt.card) {
            mine = back(); theirs = back();
            mid = h('div', { class: 'tt-vs' }, 'VS');
            controls = h('div', { class: 'tt-wait' }, 'Shuffling and dealing…');
        } else {
            mine = renderCard(tt.card.display, { scale: sc, tilt: true });
            if (tt.phase === 'result' && r) {
                theirs = renderCard(r.them.display, { scale: sc, flipped: false, tilt: false });
                setTimeout(() => theirs._flip && theirs._flip(), 60);
            } else if (tt.phase === 'end' && tt.lastThem) {
                theirs = renderCard(tt.lastThem.display, { scale: sc, tilt: false });
            } else {
                theirs = back();
            }
            if (r) tt.lastThem = r.them;
            mid = h('div', { class: 'tt-vs' }, 'VS');
        }

        const colMine = h('div', { class: 'tt-col' }, h('div', { class: 'tt-who' }, 'YOUR CARD'), mine);
        const colTheirs = h('div', { class: 'tt-col' }, h('div', { class: 'tt-who' }, `${(tt.opponent || 'THEIR').toUpperCase()}'S CARD`), theirs);

        if (tt.phase === 'choose') {
            const c = tt.card;
            if (tt.chooser) {
                controls = h('div', { class: 'tt-pick' },
                    h('div', { class: 'tt-prompt' }, tt.sent ? 'Locked in…' : 'Your pick: which stat beats theirs?'),
                    h('div', { class: 'tt-btns' },
                        h('button', { class: 'tt-btn att', disabled: tt.sent ? 'true' : null, onclick: () => ttChoose('att') }, h('span', null, 'ATTACK'), h('b', null, String(c.att)), c.boost ? h('i', null, `+${c.boost} bonus`) : null),
                        h('button', { class: 'tt-btn def', disabled: tt.sent ? 'true' : null, onclick: () => ttChoose('def') }, h('span', null, 'DEFENCE'), h('b', null, String(c.def)), c.boost ? h('i', null, `+${c.boost} bonus`) : null),
                    ),
                    h('div', { class: 'tt-timer', 'data-tt-deadline': String(tt.deadline) }, ''),
                );
            } else {
                controls = h('div', { class: 'tt-wait' }, `${tt.opponent} is choosing a stat…`, h('div', { class: 'tt-timer', 'data-tt-deadline': String(tt.deadline) }, ''));
            }
        } else if (tt.phase === 'result' && r) {
            const word = { win: 'YOU WIN THE ROUND', lose: `${(tt.opponent || '').toUpperCase()} WINS THE ROUND`, draw: 'DRAW' }[r.outcome];
            colMine.appendChild(ttStatLine(r.you, r.stat, r.yourValue, r.outcome === 'win' ? 'win' : r.outcome === 'lose' ? 'lose' : ''));
            colTheirs.appendChild(ttStatLine(r.them, r.stat, r.theirValue, r.outcome === 'lose' ? 'win' : r.outcome === 'win' ? 'lose' : ''));
            controls = h('div', { class: 'tt-banner ' + r.outcome }, word);
        } else if (tt.phase === 'end') {
            const e = tt.end;
            const title = e.outcome === 'win' ? 'YOU WIN!' : e.outcome === 'lose' ? 'YOU LOSE' : 'DRAW';
            const sub = e.forfeit ? `${e.opponent} left the game.` + (e.pot ? ` You take the ${ttMoney(e.pot)} pot.` : '')
                : e.outcome === 'win' ? (e.pot ? `You take the ${ttMoney(e.pot)} pot.` : 'Bragging rights are yours.')
                : e.outcome === 'lose' ? (e.bet ? `You lost your ${ttMoney(e.bet)} bet.` : 'Better luck next time.')
                : (e.bet ? 'Bets returned.' : 'Nobody wins this one.');
            controls = h('div', { class: 'tt-end ' + e.outcome }, h('div', { class: 'tt-end-t' }, title), h('div', { class: 'tt-end-s' }, `${e.score.you} – ${e.score.them}  ·  ${sub}`),
                h('button', { class: 'btn primary', onclick: () => { tt = null; close(); } }, 'Close'));
        }

        const leave = h('button', { class: 'btn tt-leave' }, 'Leave game');
        let armed = false;
        leave.addEventListener('click', () => {
            if (!armed) { armed = true; leave.textContent = 'Forfeit? Click again'; setTimeout(() => { armed = false; leave.textContent = 'Leave game'; }, 3000); return; }
            post('ttForfeit', {});
        });

        root.appendChild(h('div', { class: 'overlay tt' },
            head,
            h('div', { class: 'tt-table' }, colMine, mid, colTheirs),
            controls,
            tt.phase !== 'end' ? leave : null,
        ));
    }
    setInterval(() => {
        document.querySelectorAll('[data-tt-deadline]').forEach(el => {
            const s = Math.max(0, Math.ceil((Number(el.getAttribute('data-tt-deadline')) - Date.now()) / 1000));
            el.textContent = s > 0 ? `${s}s` : '';
            el.classList.toggle('low', s <= 5);
        });
    }, 250);

    /* ----- grade reveal (collecting from the grader) ----- */
    function gradeReveal(data) {
        clear();
        mode = 'reveal';
        const slabs = (data && data.slabs) || [];
        let i = 0;
        const timers = [];
        const later = (ms, fn) => timers.push(setTimeout(fn, ms));
        function money(n) { return '£' + Math.floor(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
        function show() {
            timers.forEach(clearTimeout); timers.length = 0;
            root.innerHTML = '';
            const s = slabs[i];
            if (!s) return close();
            const card = s.card, g = card.graded || {};
            const scale = Math.max(0.5, Math.min(1.15, (window.innerHeight - 280) / 560));
            const face = slabFace(card);
            face.classList.add('gr-slab');
            const label = face.querySelector('.slab-label');
            const cover = h('div', { class: 'gr-cover' }, h('div', { class: 'gr-cover-t' }, g.brand || 'GRADING'), h('div', { class: 'gr-cover-s' }, 'Your grade is…'));
            if (label) label.appendChild(cover);
            const wrap = h('div', { class: 'gr-wrap', style: { width: `${330 * scale}px`, height: `${560 * scale}px` } },
                h('div', { class: 'gr-inner', style: { transform: `scale(${scale})` } }, face));

            const pop = s.pop;
            const popLine = pop && pop.total > 0
                ? (pop.higher === 0 ? `Pop ${pop.same} at ${g.grade}  ·  none graded higher` : `Pop ${pop.same} at ${g.grade}  ·  ${pop.higher} graded higher`) + (pop.label && pop.label !== 'Base' ? `  (${pop.label})` : '')
                : null;
            const verdict = h('div', { class: 'gr-verdict' },
                h('div', { class: 'v-grade' }, `${g.label || ''} ${g.grade}`),
                h('div', { class: 'v-sub' }, card.label || ''),
                popLine ? h('div', { class: 'v-pop' }, popLine) : null,
                s.value ? h('div', { class: 'v-val' }, `Worth about ${money(s.value)}`) : null,
            );
            const last = i >= slabs.length - 1;
            const btns = h('div', { class: 'btn-row gr-btns' },
                h('button', { class: 'btn', onclick: () => { timers.forEach(clearTimeout); viewCard({ card }); } }, 'Look closer'),
                h('button', { class: 'btn primary', onclick: () => { if (last) close(); else { i++; show(); } } }, last ? 'Done' : `Next (${slabs.length - i - 1} more)`),
            );
            root.appendChild(h('div', { class: 'overlay gr-stage' },
                slabs.length > 1 ? h('div', { class: 'gr-count' }, `${i + 1} of ${slabs.length}`) : null,
                wrap, verdict, btns));

            later(1300, () => { cover.classList.add('open'); sfx(sfxCfg.flip); });
            later(1900, () => {
                face.classList.add('drop');
                if (g.grade >= 9) sfx(sfxCfg.rare);
                if (g.grade === 10) {
                    face.classList.add('gem');
                    const fl = h('div', { class: 'gr-flash' });
                    document.body.appendChild(fl);
                    setTimeout(() => fl.remove(), 1100);
                    for (let k = 0; k < 50; k++) {
                        const p = h('i', { class: 'bh-spark gr-spark', style: { left: `${50 + (Math.random() - 0.5) * 16}%`, top: '40%', '--dx': `${(Math.random() - 0.5) * 1100}px`, '--dy': `${-150 - Math.random() * 500}px`, '--r': `${Math.random() * 720}deg`, 'animation-delay': `${Math.random() * 0.2}s`, background: ['#f7d774', '#fff', '#ffe9a3'][k % 3] } });
                        document.body.appendChild(p);
                        setTimeout(() => p.remove(), 2200);
                    }
                }
            });
            later(2300, () => face.classList.add('subs'));
            later(2700, () => { verdict.classList.add('show'); btns.classList.add('show'); });
        }
        show();
    }

    /* ----- inspect with the magnifier ----- */
    const barCol = v => v >= 8.5 ? '#3ecf8e' : v >= 6.5 ? '#f7d774' : v >= 4.5 ? '#f5a524' : '#f25f5c';
    function scoreBars(sc) {
        return h('div', { class: 'ins-bars' }, [['Centering', sc.centering], ['Corners', sc.corners], ['Edges', sc.edges], ['Surface', sc.surface]].map(([k, v]) =>
            h('div', { class: 'ins-bar' }, h('span', null, k), h('div', { class: 'ins-track' }, h('div', { class: 'ins-fill', style: { width: `${v * 10}%`, background: barCol(v) } })), h('b', null, String(v)))));
    }
    function inspectCard(card, back) {
        clear();
        mode = 'view';
        const cond = card.cond;
        const S = Math.max(0.8, Math.min(1.5, (window.innerHeight - 160) / 420));
        const holder = h('div', { class: 'ins-card', style: { width: `${300 * S}px`, height: `${420 * S}px` } },
            h('div', { class: 'ins-scale', style: { transform: `scale(${S})` } }, condFace(card)));
        const Z = 3, R = 100;
        const lens = h('div', { class: 'ins-lens' }, h('div', { class: 'ins-lens-in', style: { transform: `scale(${S * Z})` } }, condFace(card)));
        holder.appendChild(lens);
        holder.addEventListener('mousemove', e => {
            const r = holder.getBoundingClientRect(), x = e.clientX - r.left, y = e.clientY - r.top;
            lens.style.display = 'block';
            lens.style.left = `${x - R}px`; lens.style.top = `${y - R}px`;
            lens.firstChild.style.left = `${R - x * Z}px`; lens.firstChild.style.top = `${R - y * Z}px`;
        });
        holder.addEventListener('mouseleave', () => { lens.style.display = 'none'; });
        const issues = (cond.issues || []);
        const panel = h('div', { class: 'ins-panel' },
            h('div', { class: 'ins-title' }, card.label || ''),
            h('div', { class: 'ins-sub' }, 'Magnifier · 3× zoom'),
            h('div', { class: 'ins-grade' }, h('div', { class: 'ins-badge' }, String(cond.scores.overall)), h('div', null, h('div', { class: 'ins-word' }, cond.scores.word), h('div', { class: 'ins-note' }, 'What a grader would most likely give it'))),
            h('div', { class: 'ins-sec' }, 'Scores'), scoreBars(cond.scores),
            h('div', { class: 'ins-sec' }, issues.length ? `Found ${issues.length} issue${issues.length > 1 ? 's' : ''}` : 'No flaws found'),
            h('div', { class: 'ins-issues' }, issues.map((i, n) => h('div', { class: 'ins-issue' },
                h('span', { class: 'ins-n' + (i.sev === 'major' ? ' bad' : '') }, String(n + 1)), h('span', { class: 'ins-t' }, i.label),
                h('span', { class: 'ins-fix' + (i.fix ? ' ok' : '') }, i.fix ? i.fix : 'Permanent')))),
            h('div', { class: 'btn-row' }, h('button', { class: 'btn', onclick: back }, 'Back')),
        );
        root.appendChild(h('div', { class: 'overlay ins-wrap still' }, h('div', { class: 'ins-row' }, holder, panel),
            h('div', { class: 'hint' }, 'Move the magnifier over the card')));
    }

    /* ----- cleaning bench: the card is a prop on the table, this is the see-through control layer ----- */
    function makeCloth(damp) {
  const S = 260, c = document.createElement('canvas'); c.width = c.height = S; const g = c.getContext('2d');
  let seed = damp ? 77 : 41; const rr = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  // a square microfibre cloth, pinched in the middle, one corner folded over
  const P = [[34, 44], [222, 30], [236, 214], [40, 228]];
  const wavy = (x1, y1, x2, y2, amp, n) => { const pts = []; for (let i = 0; i <= n; i++) { const t = i / n; const nx = -(y2 - y1), ny = x2 - x1, L = Math.hypot(nx, ny); const w = Math.sin(t * Math.PI * 3 + rr()) * amp * Math.sin(t * Math.PI); pts.push([x1 + (x2 - x1) * t + nx / L * w, y1 + (y2 - y1) * t + ny / L * w]); } return pts; };
  const edge = []; for (let i = 0; i < 4; i++) { const A = P[i], B = P[(i + 1) % 4]; edge.push(...wavy(A[0], A[1], B[0], B[1], 6, 24).slice(i ? 1 : 0)); }
  const body = new Path2D(); body.moveTo(edge[0][0], edge[0][1]); edge.forEach(p => body.lineTo(p[0], p[1])); body.closePath();
  const col = damp ? [34, 80, 150] : [70, 126, 204];
  const shade = k => `rgb(${col.map(v => Math.max(0, Math.min(255, v + k)))})`;
  g.save(); g.clip(body);
  const lg = g.createLinearGradient(40, 30, 230, 230); lg.addColorStop(0, shade(26)); lg.addColorStop(.5, shade(0)); lg.addColorStop(1, shade(-34));
  g.fillStyle = lg; g.fillRect(0, 0, S, S);
  // pinch wrinkles radiating from where the fingers hold it
  const px = 132, py = 124;
  for (let k = 0; k < 11; k++) {
    const a = k / 11 * 6.283 + rr() * .4, L = 70 + rr() * 60, w = 8 + rr() * 10;
    const x2 = px + Math.cos(a) * L, y2 = py + Math.sin(a) * L, mx = px + Math.cos(a + .25) * L * .5, my = py + Math.sin(a + .25) * L * .5;
    g.save(); g.filter = 'blur(5px)'; g.lineCap = 'round';
    const sx0 = px + Math.cos(a) * 22, sy0 = py + Math.sin(a) * 22;
    g.strokeStyle = 'rgba(6,18,50,.34)'; g.lineWidth = w; g.beginPath(); g.moveTo(sx0, sy0); g.quadraticCurveTo(mx, my, x2, y2); g.stroke();
    g.strokeStyle = 'rgba(255,255,255,.20)'; g.lineWidth = w * .4; g.beginPath(); g.moveTo(sx0 + 4, sy0 - 4); g.quadraticCurveTo(mx + 4, my - 4, x2 + 4, y2 - 4); g.stroke();
    g.restore();
  }
  // the pinched bump catches the light
  g.save(); g.filter = 'blur(10px)'; g.fillStyle = 'rgba(255,255,255,.22)'; g.beginPath(); g.ellipse(px - 4, py - 6, 26, 20, -.5, 0, 7); g.fill(); g.restore();
  // pile texture
  const id = g.getImageData(0, 0, S, S), d = id.data;
  for (let i = 0; i < d.length; i += 4) { const n = (rr() - .5) * 22; d[i] += n; d[i + 1] += n; d[i + 2] += n; }
  g.putImageData(id, 0, 0);
  // hemmed edge
  g.lineWidth = 14; g.strokeStyle = damp ? 'rgba(8,24,60,.65)' : 'rgba(16,40,96,.6)'; g.stroke(body);
  g.setLineDash([3, 4]); g.lineWidth = 1.2; g.strokeStyle = 'rgba(215,228,255,.5)';
  g.save(); g.translate(135, 129); g.scale(.935, .93); g.translate(-135, -129); g.stroke(body); g.restore(); g.setLineDash([]);
  if (damp) { g.save(); g.filter = 'blur(6px)'; for (let k = 0; k < 8; k++) { g.fillStyle = 'rgba(255,255,255,.2)'; g.beginPath(); g.ellipse(60 + rr() * 150, 60 + rr() * 150, 16 + rr() * 16, 5 + rr() * 5, rr() * 3, 0, 7); g.fill(); } g.restore(); }
  g.restore();
  // folded-over corner (underside is lighter), with a shadow under it
  const f = new Path2D(); f.moveTo(236, 214); f.lineTo(168, 222); f.quadraticCurveTo(190, 196, 228, 150); f.closePath();
  g.save(); g.filter = 'blur(6px)'; g.fillStyle = 'rgba(0,0,20,.45)'; g.translate(-6, -4); g.fill(f); g.restore();
  g.save(); g.clip(f); const fg = g.createLinearGradient(236, 214, 190, 180); fg.addColorStop(0, shade(40)); fg.addColorStop(1, shade(8)); g.fillStyle = fg; g.fillRect(0, 0, S, S);
  const fd = g.getImageData(150, 140, 100, 100), dd = fd.data; for (let i = 0; i < dd.length; i += 4) { const n = (rr() - .5) * 20; dd[i] += n; dd[i + 1] += n; dd[i + 2] += n; } g.putImageData(fd, 150, 140);
  g.restore();
  g.lineWidth = 3; g.strokeStyle = 'rgba(12,30,80,.55)'; g.stroke(f);
  const out = document.createElement('canvas'); out.width = out.height = S; const o = out.getContext('2d');
  o.filter = 'blur(.7px)'; o.drawImage(c, 0, 0);
  return out;
}

    let clean = null;
    // map a screen point to the card (0-1) using the 4 projected corners (TL, TR, BR, BL)
    function quadToSquare(q) {
        // square -> quad (Heckbert), then invert
        const [x0, y0] = q[0], [x1, y1] = q[1], [x2, y2] = q[2], [x3, y3] = q[3];
        const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3, dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
        const den = dx1 * dy2 - dx2 * dy1;
        const g = (dx3 * dy2 - dx2 * dy3) / den, hh = (dx1 * dy3 - dx3 * dy1) / den;
        const a = x1 - x0 + g * x1, b = x3 - x0 + hh * x3, c = x0, d = y1 - y0 + g * y1, e = y3 - y0 + hh * y3, f = y0;
        // inverse of [[a,b,c],[d,e,f],[g,h,1]]
        const A = e - f * hh, B = c * hh - b, C = b * f - c * e, D = f * g - d, E = a - c * g, F = c * d - a * f, G = d * hh - e * g, H = b * g - a * hh, I = a * e - b * d;
        return (x, y) => { const w = G * x + H * y + I; return [(A * x + B * y + C) / w, (D * x + E * y + F) / w]; };
    }

    function cleanStart(data) {
        clear();
        mode = 'clean';
        const card = data.card || {};
        const tools = data.tools || {};
        const sim = window.CondFX.create((card.cond && card.cond.c) || {});
        const st = clean = {
            sim, tool: 'cloth', corners: null, map: null, flipped: false, down: false, last: null,
            queue: [], spots: [], pressure: 0, scratches: 0, sprayed: false, sprayUsed: false, ang: 0, lastScreen: null,
        };
        const clothC = h('canvas', { class: 'cl-cloth', width: '260', height: '260' });
        const clothDry = makeCloth(false), clothDamp = makeCloth(true);
        const bottle = h('div', { class: 'cl-bottle' }); bottle.innerHTML = `<svg viewBox="0 0 70 110"><defs><linearGradient id="bt" x1="0" x2="1"><stop offset="0" stop-color="#bfe9dc" stop-opacity=".75"/><stop offset=".45" stop-color="#e9fff8" stop-opacity=".9"/><stop offset="1" stop-color="#8ccfb9" stop-opacity=".8"/></linearGradient><linearGradient id="lq" x1="0" x2="1"><stop offset="0" stop-color="#3fae8c"/><stop offset=".5" stop-color="#7fe0c0"/><stop offset="1" stop-color="#2f8e70"/></linearGradient></defs>
  <path d="M6 10 L30 6 L34 14 L22 18 Z" fill="#2a2f38"/><rect x="24" y="4" width="16" height="22" rx="3" fill="#353b46"/><path d="M40 12 L48 12 L48 20 L40 22 Z" fill="#2a2f38"/>
  <rect x="27" y="24" width="10" height="8" fill="#e5e7eb"/><path d="M20 32 H44 Q50 32 50 40 V100 Q50 106 44 106 H20 Q14 106 14 100 V40 Q14 32 20 32 Z" fill="url(#bt)" stroke="rgba(255,255,255,.6)"/>
  <path d="M16 58 H48 V99 Q48 104 43 104 H21 Q16 104 16 99 Z" fill="url(#lq)" opacity=".85"/><rect x="19" y="64" width="26" height="22" rx="3" fill="#fff" opacity=".92"/>
  <text x="32" y="74" text-anchor="middle" font-family="Barlow Condensed, sans-serif" font-weight="800" font-size="6.5" fill="#1d4a3a">CARD</text><text x="32" y="82" text-anchor="middle" font-family="Barlow Condensed, sans-serif" font-weight="800" font-size="6.5" fill="#1d4a3a">CLEANER</text>
  <rect x="18" y="36" width="4" height="60" rx="2" fill="#fff" opacity=".35"/></svg>`;
        const progress = h('i', { class: 'cl-fill' });
        const risk = h('i', { class: 'cl-fill' });
        const toolBtn = (id, name, desc, uses, max) => h('div', { class: 'cl-tool' + (id === 'cloth' ? ' on' : '') + (uses <= 0 ? ' off' : ''), 'data-tool': id },
            h('div', { class: 'cl-ico cl-ico-' + id }), h('div', null, h('div', { class: 'cl-nm' }, name), h('div', { class: 'cl-ds' }, desc)), h('span', { class: 'cl-uses' }, `${uses}/${max}`));
        const tCloth = toolBtn('cloth', 'Microfibre Cloth', 'Dust, lint, fingerprints · safe', tools.cloth || 0, tools.clothMax || 5);
        const tSpray = toolBtn('spray', 'Card Cleaner Spray', 'Right-click to spray, then wipe · dirt & stains', tools.spray || 0, tools.sprayMax || 3);
        const hint = h('div', { class: 'cl-hint' }, 'Hold the left mouse button and wipe the card');
        const setTool = t => {
            if (t === 'spray' && !(tools.spray > 0)) return;
            st.tool = t; tCloth.classList.toggle('on', t === 'cloth'); tSpray.classList.toggle('on', t === 'spray');
            hint.textContent = t === 'cloth' ? 'Hold the left mouse button and wipe the card' : 'Right-click to spray the dirt, then hold left mouse and wipe · rush it and you will scratch it';
            riskBox.style.opacity = t === 'spray' ? '1' : '.3';
        };
        tCloth.onclick = () => setTool('cloth'); tSpray.onclick = () => setTool('spray');
        const riskBox = h('div', { style: { opacity: '.3' } }, h('div', { class: 'cl-sec' }, 'Pressure'), h('div', { class: 'cl-meter' }, risk));
        const finish = ok => {
            flush();
            const rem = sim.remaining();
            post(ok ? 'cleanDone' : 'cleanCancel', ok ? { result: { dust: rem.dust, finger: rem.finger, dirt: rem.dirt, stain: rem.stain, scratch: st.scratches, sprayed: st.sprayUsed } } : {});
            clear();
        };
        const panel = h('div', { class: 'cl-panel' },
            h('div', { class: 'cl-title' }, 'Cleaning'), h('div', { class: 'cl-sub' }, card.label || ''),
            h('div', { class: 'cl-sec' }, 'Tools'), tCloth, tSpray,
            h('div', { class: 'cl-sec' }, 'Cleaned'), h('div', { class: 'cl-meter' }, progress),
            riskBox,
            h('div', { class: 'cl-keys' }, 'Scroll  zoom   ·   F  flip the card   ·   Esc  stop'),
            h('div', { class: 'btn-row' }, h('button', { class: 'btn primary', onclick: () => finish(true) }, 'Done'), h('button', { class: 'btn', onclick: () => finish(false) }, 'Cancel')),
        );
        // the card itself: our card in 3D, lying on the mat under the camera
        const S = Math.max(0.9, Math.min(1.9, (window.innerHeight - 180) / 420));
        const front = h('div', { class: 'cl-face cl-front' }, cardFace(card), sim.el, h('div', { class: 'cl-sheen' }));
        const back = h('div', { class: 'cl-face cl-back' }, cardBack(), h('div', { class: 'cl-sheen' }));
        const edges = [-1, 0, 1].map(z => h('div', { class: 'cl-edge', style: { transform: `translateZ(${z}px)` } }));
        const cardObj = h('div', { class: 'cl-obj' }, edges, back, front);
        const cardBox = h('div', { class: 'cl-card', style: { width: `${300 * S}px`, height: `${420 * S}px` } },
            h('div', { class: 'cl-shadow' }), h('div', { class: 'cl-scale', style: { transform: `scale(${S})` } }, cardObj));
        st.front = front; st.cardObj = cardObj; st.zoom = 1;
        const setPose = () => { cardObj.style.transform = `scale(${st.zoom}) rotateX(${st.tiltX || 0}deg) rotateY(${st.flipped ? 180 : 0}deg)`; };
        st.setPose = setPose; setPose();
        const layer = h('div', { class: 'cl-layer' }, cardBox, panel, hint, clothC, bottle);
        root.appendChild(layer);
        const cctx = clothC.getContext('2d');
        let skin = null;
        const setSkin = k => { if (skin === k) return; skin = k; cctx.clearRect(0, 0, 260, 260); cctx.drawImage(k === 'damp' ? clothDamp : clothDry, 0, 0); };

        function flush() { st.queue = []; }
        st.flushTimer = setInterval(flush, 60);
        st.dryTimer = setInterval(() => { st.spots.forEach(p => { p.life -= 0.03; }); st.spots = st.spots.filter(p => p.life > 0); sim.dry(0.035); }, 250);
        st.progTimer = setInterval(() => {
            const rem = sim.remaining(), keys = ['dust', 'finger', 'dirt', 'stain'].filter(k => (sim.cond[k] || 0) > 0.03);
            const pct = keys.length ? 100 - keys.reduce((a, k) => a + rem[k], 0) / keys.length * 100 : 100;
            progress.style.width = `${Math.max(0, Math.min(100, pct))}%`;
        }, 300);
        const wetAt = (x, y) => st.spots.reduce((m, p) => Math.max(m, p.life * Math.max(0, 1 - Math.hypot(x - p.x, y - p.y) / p.r)), 0);
        const toCard = (cx, cy) => {
            if (st.flipped) return null;
            const r = st.front.getBoundingClientRect();
            const u = (cx - r.left) / r.width, v = (cy - r.top) / r.height;
            if (u < 0 || u > 1 || v < 0 || v > 1) return null;
            return [u * window.CondFX.W, v * window.CondFX.H];
        };

        st.onMove = e => {
            const onPanel = panel.contains(e.target);
            const showBottle = st.tool === 'spray' && !st.down;
            bottle.style.display = !onPanel && showBottle ? 'block' : 'none';
            clothC.style.display = !onPanel && !showBottle ? 'block' : 'none';
            layer.style.cursor = onPanel ? 'default' : 'none';
            bottle.style.left = `${e.clientX}px`; bottle.style.top = `${e.clientY}px`;
            setSkin(st.tool === 'spray' ? 'damp' : 'dry');
            if (st.lastScreen) { const dx = e.clientX - st.lastScreen.x; if (Math.abs(dx) > 1) st.ang += (Math.max(-0.5, Math.min(0.5, dx * 0.02)) - st.ang) * 0.2; }
            st.lastScreen = { x: e.clientX, y: e.clientY };
            clothC.style.left = `${e.clientX}px`; clothC.style.top = `${e.clientY}px`;
            clothC.style.transform = `rotate(${st.ang}rad) scale(${st.down ? '1.04,.94' : '1'})`;
            clothC.style.filter = st.down ? 'drop-shadow(0 3px 4px rgba(0,0,0,.55))' : 'drop-shadow(0 16px 14px rgba(0,0,0,.55))';
            if (!st.down) return;
            const p = toCard(e.clientX, e.clientY);
            if (!p) { st.last = null; return; }
            const [x, y] = p;
            const speed = st.last ? Math.hypot(x - st.last[0], y - st.last[1]) : 0;
            if (st.last && speed < 0.5) return;
            const softS = st.tool === 'cloth' ? 0.2 : 0.12;
            let grime = 0, wetS = 0;
            if (st.tool === 'spray') {
                const w = wetAt(x, y);
                grime = w > 0.05 ? 0.22 * w : 0;
                wetS = 0.35;
                st.pressure = Math.min(100, st.pressure * 0.9 + speed * 0.9);
                risk.style.width = `${st.pressure}%`;
                risk.style.background = st.pressure > 75 ? '#f25f5c' : st.pressure > 45 ? '#f5a524' : '#3ecf8e';
                if (st.pressure > 92 && !st.scratchLock && st.scratches < 3) {
                    st.scratchLock = true; st.scratches++;
                    sim.scratchAt(x, y); st.queue.push({ t: 's', x: Math.round(x), y: Math.round(y) });
                    toast('Too much pressure - you scratched the surface');
                    setTimeout(() => { st.scratchLock = false; }, 1500);
                }
            }
            sim.erase(x, y, st.ang, softS, grime, wetS);
            st.queue.push({ t: 'w', x: Math.round(x), y: Math.round(y), r: +st.ang.toFixed(3), s: softS, g: +grime.toFixed(3), w: wetS });
            st.last = p;
        };
        st.onDown = e => { if (panel.contains(e.target)) return; if (e.button === 0) { st.down = true; st.last = null; } };
        st.onUp = () => { st.down = false; st.last = null; };
        st.onCtx = e => {
            e.preventDefault();
            if (panel.contains(e.target)) return;
            if (st.tool !== 'spray') { toast('Pick the cleaner spray to spray'); return; }
            const p = toCard(e.clientX, e.clientY);
            if (!p) return;
            const seed = Math.floor(Math.random() * 1e9);
            sim.spray(p[0], p[1], seed);
            st.spots.push({ x: p[0], y: p[1], r: 80, life: 1 });
            st.queue.push({ t: 'p', x: Math.round(p[0]), y: Math.round(p[1]), s: seed });
            st.sprayUsed = true;
        };
        st.onWheel = e => { st.zoom = Math.max(0.7, Math.min(1.6, st.zoom * (e.deltaY > 0 ? 0.93 : 1.07))); setPose(); };
        st.onKey = e => {
            if (e.key === 'Escape') finish(false);
            else if (e.key === 'f' || e.key === 'F') { st.flipped = !st.flipped; setPose(); }
        };
        st.finish = finish;
        window.addEventListener('mousemove', st.onMove);
        window.addEventListener('mousedown', st.onDown);
        window.addEventListener('mouseup', st.onUp);
        window.addEventListener('contextmenu', st.onCtx);
        window.addEventListener('wheel', st.onWheel);
        window.addEventListener('keydown', st.onKey);
    }
    function cleanCorners(data) {
        if (!clean) return;
        clean.flipped = !!data.flipped;
        const pts = (data.pts || []).map(p => [p[0] * window.innerWidth, p[1] * window.innerHeight]);
        if (pts.length === 4) { clean.corners = pts; clean.map = quadToSquare(pts); }
    }
    function cleanStop() {
        const st = clean;
        if (!st) return;
        clearInterval(st.flushTimer); clearInterval(st.dryTimer); clearInterval(st.progTimer);
        window.removeEventListener('mousemove', st.onMove);
        window.removeEventListener('mousedown', st.onDown);
        window.removeEventListener('mouseup', st.onUp);
        window.removeEventListener('contextmenu', st.onCtx);
        window.removeEventListener('wheel', st.onWheel);
        window.removeEventListener('keydown', st.onKey);
        clean = null;
    }
    let toastEl = null;
    function toast(text) {
        if (!toastEl) { toastEl = h('div', { class: 'cl-toast' }); document.body.appendChild(toastEl); }
        toastEl.textContent = text; toastEl.classList.add('show');
        clearTimeout(toastEl._t); toastEl._t = setTimeout(() => toastEl.classList.remove('show'), 2400);
    }

    /* ----- peek (someone showing you a card, no focus) ----- */
    function peekCard(data) {
        clearTimeout(peekTimer);
        peekRoot.innerHTML = '';
        const el = h('div', { class: 'peek' },
            h('div', { class: 'peek-from' }, h('b', null, data.from || 'Someone'), ' is showing you'),
            renderCard(data.card, { scale: 0.62, tilt: false }),
        );
        peekRoot.appendChild(el);
        peekTimer = setTimeout(() => {
            el.classList.add('out');
            setTimeout(() => el.remove(), 400);
        }, data.duration || 8000);
    }

    /* ----- binder: a real binder - any card in any sleeve, 9 sleeves a page, flip with Previous / Next ----- */
    const PER_PAGE = 9;
    let binderState = null;

    function openBinder(data) {
        const keep = binderState || {};
        clear();
        mode = 'binder';
        binderState = { data, sleeves: {}, spread: keep.spread || 0, tray: false, busy: false, justAdded: null, sel: null };
        indexSleeves();
        renderBinder();
    }

    function indexSleeves() {
        const map = {};
        (binderState.data.filled || []).forEach(f => { map[f.slot] = f; });
        binderState.sleeves = map;
    }

    function spreadCount() {
        return Math.max(1, Math.ceil((binderState.data.pages || 2) / 2));
    }

    function currentSet() {
        return (binderState.data.sets || [])[0];
    }

    function pageLabel(spread) {
        const set = currentSet();
        return `PAGE ${spread + 1} / ${spreadCount()}` + (set ? `   ·   ${set.have}/${set.total} COLLECTED` : '');
    }

    // page counter with a box you can type a page number into (Enter to jump)
    function pageNav(spread) {
        const set = currentSet();
        const total = spreadCount();
        const input = h('input', {
            class: 'bk-page-in', type: 'text', inputmode: 'numeric', maxlength: String(String(total).length),
            value: String(spread + 1), title: 'Type a page number and press Enter',
        });
        const jump = () => {
            const n = parseInt(input.value, 10);
            if (!isNaN(n)) {
                const target = Math.min(Math.max(n, 1), total) - 1;
                if (target !== binderState.spread) goSpread(target - binderState.spread);
                input.value = String(target + 1);
            } else input.value = String(binderState.spread + 1);
            input.blur();
        };
        input.addEventListener('input', () => { input.value = input.value.replace(/[^0-9]/g, ''); });
        input.addEventListener('focus', () => input.select());
        input.addEventListener('keydown', e => {
            e.stopPropagation();
            if (e.key === 'Enter') jump();
            else if (e.key === 'Escape') { input.value = String(binderState.spread + 1); input.blur(); }
        });
        input.addEventListener('keyup', e => e.stopPropagation());
        input.addEventListener('blur', () => { if (input.value === '') input.value = String(binderState.spread + 1); });
        return h('div', { class: 'bk-page-no' },
            binderState.data.name ? h('span', { class: 'bk-name' }, binderState.data.name) : null,
            'PAGE ', input, ` / ${total}`,
            set ? h('span', { class: 'bk-page-set' }, `   ·   ${set.have}/${set.total} COLLECTED`) : null,
        );
    }

    function buildPage(spreadIdx, offset, sc) {
        const start = spreadIdx * PER_PAGE * 2 + offset + 1;
        const cells = [];
        for (let i = 0; i < PER_PAGE; i++) cells.push(pocket(start + i, sc));
        return h('div', { class: 'bk-page' }, cells);
    }

    // real page turn: the page lifts off one side and swings over the rings
    function goSpread(delta) {
        if (binderState.flipping) return;
        const next = Math.min(Math.max(binderState.spread + delta, 0), spreadCount() - 1);
        if (next === binderState.spread) return;

        const book = root.querySelector('.bk');
        const pages = book ? book.querySelectorAll(':scope > .bk-page') : [];
        if (!book || pages.length < 2) { binderState.spread = next; renderBinder(); return; }

        binderState.flipping = true;
        const sc = pocketScale();
        const [left, right] = pages;
        const forward = delta > 0;
        const newLeft = buildPage(next, 0, sc);
        const newRight = buildPage(next, PER_PAGE, sc);
        const under = forward ? right : left;       // page the leaf lifts off
        const box = { l: under.offsetLeft, t: under.offsetTop, w: under.offsetWidth, h: under.offsetHeight };
        // hinge on the middle of the rings so the page lands exactly on the other side
        const spineMid = (left.offsetLeft + left.offsetWidth + right.offsetLeft) / 2;
        const originX = spineMid - under.offsetLeft;

        const frontFace = h('div', { class: 'bk-leaf-face front' });
        const backFace = h('div', { class: 'bk-leaf-face back' });
        const leaf = h('div', {
            class: 'bk-leaf ' + (forward ? 'fwd' : 'bwd'),
            style: { left: `${box.l}px`, top: `${box.t}px`, width: `${box.w}px`, height: `${box.h}px`, 'transform-origin': `${originX}px 50%` },
        }, frontFace, backFace);

        book.replaceChild(forward ? newRight : newLeft, under);
        frontFace.appendChild(under);
        backFace.appendChild(forward ? newLeft : newRight);
        book.appendChild(leaf);
        sfx(sfxCfg.flip);

        void leaf.offsetWidth;
        leaf.classList.add('go');

        let finished = false;
        const finish = () => {
            if (finished) return;
            finished = true;
            binderState.flipping = false;
            binderState.spread = next;
            if (mode !== 'binder' || !leaf.isConnected) return;
            // settle the pages in place - no re-render, so nothing flashes
            const landed = backFace.firstElementChild;
            const other = forward ? left : right;
            if (landed && other.isConnected) book.replaceChild(landed, other);
            leaf.remove();
            const no = root.querySelector('.bk-page-in');
            if (no && document.activeElement !== no) no.value = String(next + 1);
            const prev = root.querySelector('.bk-btn.prev'), nxt = root.querySelector('.bk-btn.next');
            if (prev) prev.disabled = next === 0;
            if (nxt) nxt.disabled = next >= spreadCount() - 1;
        };
        leaf.addEventListener('transitionend', e => { if (e.target === leaf) finish(); });
        setTimeout(finish, 1000);
    }

    async function binderAction(name, payload) {
        if (binderState.busy) return;
        binderState.busy = true;
        const before = new Set(Object.keys(binderState.sleeves));
        const res = await post(name, payload);
        binderState.busy = false;
        if (mode !== 'binder') return;
        binderState.sel = null;
        if (res && res.filled) {
            binderState.data = res;
            indexSleeves();
            // show the sleeve the card landed in
            const landed = payload.target || payload.to || Object.keys(binderState.sleeves).map(Number).find(n => !before.has(String(n)));
            if (landed && (name === 'binderInsert' || name === 'binderMove')) {
                binderState.justAdded = Number(landed);
                binderState.spread = Math.floor((Number(landed) - 1) / (PER_PAGE * 2));
            }
        }
        renderBinder();
    }

    function pocketScale() {
        const byH = (window.innerHeight - 190) / 3 / 420;
        const byW = (Math.min(window.innerWidth * 0.94 - (binderState && binderState.tray ? 330 : 0), 1500) - 170) / 6 / 300;
        return Math.max(0.3, Math.min(0.62, byH, byW));
    }

    // what happens when a sleeve is clicked or has something dropped on it
    function placeInto(n, what) {
        what = what || binderState.sel;
        if (!what) return false;
        if (what.type === 'inv') {
            if (binderState.sleeves[n]) return false;
            binderAction('binderInsert', { slot: what.slot, serial: what.serial, target: n });
            return true;
        }
        if (what.type === 'sleeve' && what.n !== n) {
            binderAction('binderMove', { from: what.n, to: n });
            return true;
        }
        return false;
    }

    function setSel(sel) {
        binderState.sel = sel;
        renderBinder();
    }

    // ---- drag a card into a sleeve: the card follows your mouse, drop it on any sleeve ----
    let drag = null;

    function sleeveAt(x, y) {
        const el = document.elementFromPoint(x, y);
        const p = el && el.closest && el.closest('.bk-pocket[data-n]');
        return p ? p : null;
    }

    function startDrag(e, what, display, sourceEl) {
        if (e.button !== 0 || binderState.busy || binderState.flipping) return;
        drag = { what, display, sourceEl, x0: e.clientX, y0: e.clientY, ghost: null, over: null, hoverBtn: null, hoverTimer: null };
        window.addEventListener('pointermove', onDragMove);
        window.addEventListener('pointerup', onDragEnd, { once: true });
    }

    function onDragMove(e) {
        if (!drag) return;
        if (!drag.ghost) {
            if (Math.hypot(e.clientX - drag.x0, e.clientY - drag.y0) < 6) return; // still a click
            const sc = pocketScale();
            const card = renderCard(drag.display, { scale: sc, tilt: false });
            drag.w = 300 * sc; drag.h = 420 * sc;
            drag.ghost = h('div', { class: 'drag-ghost' }, card);
            document.body.appendChild(drag.ghost);
            drag.sourceEl.classList.add('drag-src');
            root.querySelector('.bk-wrap') && root.querySelector('.bk-wrap').classList.add('dragging');
            sfx(sfxCfg.flip);
        }
        // card follows the mouse with a little swing
        const dx = e.clientX - (drag.lx ?? e.clientX);
        drag.lx = e.clientX;
        drag.rot = ((drag.rot || 0) * 0.8) + Math.max(-12, Math.min(12, dx * 0.8)) * 0.2;
        drag.ghost.style.transform = `translate(${e.clientX - drag.w / 2}px, ${e.clientY - drag.h / 2}px) rotate(${drag.rot.toFixed(2)}deg) scale(1.06)`;

        // highlight the sleeve under the card
        const over = sleeveAt(e.clientX, e.clientY);
        if (over !== drag.over) {
            if (drag.over) drag.over.classList.remove('drop-over');
            if (over) over.classList.add('drop-over');
            drag.over = over;
        }

        // hold over PREVIOUS / NEXT to turn the page while carrying a card
        const el = document.elementFromPoint(e.clientX, e.clientY);
        const btn = el && el.closest && el.closest('.bk-btn.prev, .bk-btn.next');
        if (btn !== drag.hoverBtn) {
            clearTimeout(drag.hoverTimer);
            drag.hoverBtn = btn;
            if (btn && !btn.disabled) {
                const dir = btn.classList.contains('next') ? 1 : -1;
                drag.hoverTimer = setTimeout(function turn() {
                    if (!drag || drag.hoverBtn !== btn) return;
                    goSpread(dir);
                    drag.hoverTimer = setTimeout(turn, 1100);
                }, 450);
            }
        }
    }

    function onDragEnd(e) {
        window.removeEventListener('pointermove', onDragMove);
        if (!drag) return;
        const d = drag;
        drag = null;
        clearTimeout(d.hoverTimer);
        if (!d.ghost) return; // it was a click - the normal click handler deals with it
        binderState.justDragged = true;
        setTimeout(() => { if (binderState) binderState.justDragged = false; }, 0);
        const wrap = root.querySelector('.bk-wrap');
        if (wrap) wrap.classList.remove('dragging');
        const target = sleeveAt(e.clientX, e.clientY);
        if (target) {
            const n = Number(target.dataset.n);
            // snap the card into the sleeve, then let the server confirm
            const r = target.getBoundingClientRect();
            d.ghost.style.transition = 'transform .18s ease-out';
            d.ghost.style.transform = `translate(${r.left + r.width / 2 - d.w / 2}px, ${r.top + r.height / 2 - d.h / 2}px) rotate(0deg) scale(1)`;
            setTimeout(() => d.ghost.remove(), 180);
            target.classList.remove('drop-over');
            const ok = placeInto(n, d.what);
            if (!ok) d.sourceEl.classList.remove('drag-src');
        } else {
            // dropped somewhere else: fly back
            const r = d.sourceEl.getBoundingClientRect();
            d.ghost.style.transition = 'transform .25s ease-in';
            d.ghost.style.transform = `translate(${r.left + r.width / 2 - d.w / 2}px, ${r.top + r.height / 2 - d.h / 2}px) scale(.9)`;
            setTimeout(() => { d.ghost.remove(); d.sourceEl.classList.remove('drag-src'); }, 250);
        }
    }

    function pocket(n, sc) {
        const entry = binderState.sleeves[n];
        const sel = binderState.sel;
        if (entry && entry.display) {
            const isSel = sel && sel.type === 'sleeve' && sel.n === n;
            const el = h('div', {
                class: 'bk-pocket filled' + (binderState.justAdded === n ? ' just-added' : '') + (isSel ? ' sel' : '') + (sel && sel.type === 'sleeve' && !isSel ? ' target' : ''),
                'data-n': String(n),
                title: 'Drag to another sleeve',
                onclick: () => {
                    if (binderState.justDragged) return;
                    if (sel && sel.type === 'sleeve' && sel.n !== n) return placeInto(n);
                    setSel(isSel ? null : { type: 'sleeve', n });
                },
            },
                renderCard(entry.display, { scale: sc }),
                h('button', { class: 'bk-out', onclick: e => { e.stopPropagation(); binderAction('binderRemove', { sleeve: n }); } }, 'Take out'),
            );
            el.addEventListener('pointerdown', e => { if (!e.target.closest('.bk-out')) startDrag(e, { type: 'sleeve', n }, entry.display, el); });
            return el;
        }
        return h('div', {
            class: 'bk-pocket empty' + (sel ? ' target' : ''),
            'data-n': String(n),
            onclick: () => { if (!binderState.justDragged) placeInto(n); },
        }, h('div', { class: 'bk-empty' }, h('span', { class: 'place' }, sel ? 'PLACE HERE' : 'DROP HERE')));
    }

    // rename the binder (shown as the item name in the inventory)
    function renameBinder() {
        const old = document.querySelector('.bk-rename');
        if (old) { old.remove(); return; }
        const input = h('input', { class: 'bk-rename-in', type: 'text', maxlength: '30', placeholder: 'e.g. Liverpuddle collection', value: binderState.data.name || '' });
        const save = () => {
            post('binderRename', { name: input.value }).then(res => {
                if (res) { binderState.data.name = res.name || null; box.remove(); renderBinder(); }
            });
        };
        input.addEventListener('keydown', e => { e.stopPropagation(); if (e.key === 'Enter') save(); if (e.key === 'Escape') box.remove(); });
        input.addEventListener('keyup', e => e.stopPropagation());
        const box = h('div', { class: 'bk-rename' },
            h('div', { class: 'bk-rename-t' }, 'Name this binder'),
            input,
            h('div', { class: 'bk-rename-row' },
                h('button', { class: 'bk-btn', onclick: () => box.remove() }, 'CANCEL'),
                h('button', { class: 'bk-btn add', onclick: save }, 'SAVE'),
            ),
        );
        root.appendChild(box);
        setTimeout(() => { input.focus(); input.select(); }, 30);
    }

    function cycleCover() {
        const list = (binderState.data.themes || []).filter(t => t.owned);
        if (list.length < 2) return;
        const cur = binderState.data.theme && binderState.data.theme.id;
        const i = list.findIndex(t => t.id === cur);
        const nx = list[(i + 1) % list.length];
        post('binderTheme', { id: nx.id }).then(r => { if (r && r.id) { binderState.data.theme = r; renderBinder(); } });
    }

    function renderBinder() {
        const trayEl = root.querySelector('.bk-tray-list');
        const keepTray = trayEl ? trayEl.scrollTop : 0;
        root.innerHTML = '';

        const { data } = binderState;
        const set = currentSet();
        const inv = data.inventory || [];
        const s = pocketScale();
        const total = spreadCount();
        binderState.spread = Math.min(binderState.spread, total - 1);

        const th = data.theme;
        const bookStyle = { '--ps': String(s) };
        if (th) { bookStyle['--bk-cover'] = th.cover; bookStyle['--bk-ring'] = th.ring; bookStyle['--bk-edge'] = th.edge; bookStyle['--bk-spine'] = th.spine; }
        const book = h('div', { class: 'bk' + (binderState.busy ? ' busy' : ''), style: bookStyle },
            buildPage(binderState.spread, 0, s),
            h('div', { class: 'bk-spine' }),
            buildPage(binderState.spread, PER_PAGE, s),
        );

        const nav = h('div', { class: 'bk-nav' },
            h('button', { class: 'bk-btn prev', onclick: () => goSpread(-1), disabled: binderState.spread === 0 ? 'true' : null }, '‹  PREVIOUS'),
            pageNav(binderState.spread),
            binderState.sel ? h('button', { class: 'bk-btn', onclick: () => setSel(null) }, 'CANCEL') : null,
            h('button', { class: 'bk-btn add' + (binderState.tray ? ' on' : ''), onclick: () => { binderState.tray = !binderState.tray; binderState.sel = null; renderBinder(); } },
                `ADD CARDS${inv.length ? ` (${inv.length})` : ''}`),
            h('button', { class: 'bk-btn next', onclick: () => goSpread(1), disabled: binderState.spread >= total - 1 ? 'true' : null }, 'NEXT  ›'),
            h('button', { class: 'bk-btn', onclick: renameBinder }, 'RENAME'),
            (data.themes || []).filter(t => t.owned).length > 1 ? h('button', { class: 'bk-btn', onclick: cycleCover, title: 'Change the binder cover' }, 'COVER') : null,
            h('button', { class: 'bk-btn close', onclick: close, 'aria-label': 'Close binder' }, 'CLOSE'),
        );

        // your loose cards: click to pick one up then click a sleeve, drag it onto a sleeve, or double-click for the next empty sleeve
        let tray = null;
        if (binderState.tray) {
            const sel = binderState.sel;
            const invCard = i => {
                const isSel = sel && sel.type === 'inv' && sel.slot === i.slot;
                const el = h('div', {
                    class: 'b-inv' + (isSel ? ' sel' : ''),
                    title: 'Drag into a sleeve · double-click for the next empty sleeve',
                    onclick: () => { if (!binderState.justDragged) setSel(isSel ? null : { type: 'inv', slot: i.slot, serial: i.serial }); },
                    ondblclick: () => binderAction('binderInsert', { slot: i.slot, serial: i.serial }),
                },
                    renderCard(i.display, { scale: 0.4, tilt: false }),
                    h('div', { class: 'b-inv-label' + (i.owned ? ' dupe' : ' new') }, isSel ? 'Pick a sleeve' : (i.owned ? 'Duplicate' : 'New')),
                );
                el.addEventListener('pointerdown', e => startDrag(e, { type: 'inv', slot: i.slot, serial: i.serial }, i.display, el));
                return el;
            };
            tray = h('div', { class: 'bk-tray' },
                h('div', { class: 'b-side-head' }, 'Your cards', h('span', null, String(inv.length))),
                h('div', { class: 'b-side-list bk-tray-list' },
                    inv.length === 0 ? h('div', { class: 'b-side-empty' }, 'No loose cards in your inventory') : null,
                    inv.map(invCard),
                ),
            );
        }

        root.appendChild(h('div', { class: 'overlay clear bk-wrap' + (binderState.tray ? ' tray-open' : '') + (binderState.rendered ? ' still' : '') + (binderState.trayShown ? ' tray-still' : '') }, book, nav, tray));
        binderState.rendered = true;
        binderState.trayShown = !!binderState.tray;
        const nt = root.querySelector('.bk-tray-list');
        if (nt) nt.scrollTop = keepTray;
        binderState.justAdded = null;
    }

    window.addEventListener('resize', () => { if (mode === 'binder') renderBinder(); });

    /* ---------------------------------------------------------------- wiring */
    const handlers = {
        openPack,
        viewCard,
        peekCard,
        binder: openBinder,
        cleanStart,
        cleanCorners,
        gradeReveal,
        ttStart, ttRound, ttResult, ttEnd,
        appraisal,
        admin,
        close: () => { clear(); tt = null; adm = null; },
    };

    window.addEventListener('message', e => {
        const msg = e.data;
        if (!msg || typeof msg !== 'object') return;
        if (msg.sounds && typeof msg.sounds === 'object') sfxCfg = Object.assign({}, sfxCfg, msg.sounds);
        if (msg.action === 'sfx') { sfx(msg.data && msg.data.name); return; }
        if ('photoUrl' in msg) photoUrl = typeof msg.photoUrl === 'string' ? msg.photoUrl : '';
        if (msg.cardBacks && typeof msg.cardBacks === 'object') backs = msg.cardBacks;
        if ('cardBack' in msg) backImage = typeof msg.cardBack === 'string' && msg.cardBack !== '' ? msg.cardBack : null;
        const fn = handlers[msg.action] || (window.ascardV2 && window.ascardV2.handlers && window.ascardV2.handlers[msg.action]);
        if (fn) fn(msg.data || {});
    });

    window.addEventListener('keyup', e => {
        if (e.target && e.target.tagName === 'INPUT') return;
        if (mode === 'tt' && tt && tt.phase !== 'end') return;   // leave with the button (it forfeits)
        if (mode === 'v2lock') return;                            // battle screen: leave with its own buttons
        if ((e.key === 'Escape' || e.key === 'Backspace') && mode && mode !== 'clean') close();
        if (mode === 'binder' && e.key === 'ArrowRight') goSpread(1);
        if (mode === 'binder' && e.key === 'ArrowLeft') goSpread(-1);
    });

    // v2 screens (html/v2.js) borrow these
    window.ascardHost = { h, post, sfx, renderCard, clear, close, root, IN_GAME, setMode: m => { mode = m; }, getMode: () => mode, sfxCfg: () => sfxCfg };
    // browser testing: window.ascard.openPack({...})
    window.ascardRender = { cardFace, cardBack, condFace, h };
    if (!IN_GAME) { window.ascard = handlers; window.ascard._face = c => cardFace(c); window.ascard._slab = c => slabFace(c); }
})();
