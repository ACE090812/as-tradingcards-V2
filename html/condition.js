/* Card condition overlays: dust, fingerprints, dirt, stains, scratches, print lines,
   edge whitening, water damage, dinged corners and creases, drawn over a card.
   Everything is laid out from the card's seed, so the NUI and the DUI on the table
   draw exactly the same flaws. Shared by app.js (NUI) and dui.html (the table). */
(() => {
    'use strict';
    const W = 600, H = 840;

    function rng(seed) {
        let s = (Math.abs(Math.floor(seed)) % 2147483646) + 1;
        return () => { s = (s * 16807) % 2147483647; return (s - 1) / 2147483646; };
    }
    function mkCanvas(cls) {
        const c = document.createElement('canvas');
        c.width = W; c.height = H; c.className = 'cfx-layer ' + (cls || '');
        return c;
    }
    function blob(g, r, x, y, rad, col, blur) {
        g.save(); g.filter = `blur(${blur}px)`; g.fillStyle = col; g.beginPath();
        for (let a = 0; a <= 6.3; a += 0.35) { const rr = rad * (0.7 + r() * 0.45); g.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr * 0.85); }
        g.closePath(); g.fill(); g.restore();
    }

    const DRAW = {
        dust(g, r, a) {
            const n = Math.round(260 * a);
            for (let i = 0; i < n; i++) {
                const x = r() * W, y = r() * H, rad = 0.6 + r() * 1.6;
                g.fillStyle = `rgba(${r() < 0.7 ? '235,235,230' : '60,55,50'},${0.25 + r() * 0.45})`;
                g.beginPath(); g.arc(x, y, rad, 0, 7); g.fill();
            }
            g.lineCap = 'round';
            for (let i = 0; i < Math.round(14 * a); i++) {
                const x = 20 + r() * (W - 40), y = 20 + r() * (H - 40);
                g.strokeStyle = `rgba(240,240,240,${0.35 + r() * 0.25})`; g.lineWidth = 0.8 + r() * 0.6;
                g.beginPath(); g.moveTo(x, y);
                g.bezierCurveTo(x + (r() - 0.5) * 28, y + (r() - 0.5) * 28, x + (r() - 0.5) * 44, y + (r() - 0.5) * 44, x + (r() - 0.5) * 60, y + (r() - 0.5) * 60); g.stroke();
            }
        },
        finger(g, r, a) {
            const prints = a > 0.5 ? 3 : a > 0.2 ? 2 : 1;
            for (let p = 0; p < prints; p++) {
                const cx = W * (0.25 + r() * 0.5), cy = H * (0.2 + r() * 0.6), s = 0.8 + r() * 0.3, rot = (r() - 0.5) * 1.6;
                g.save(); g.translate(cx, cy); g.rotate(rot);
                for (let k = 0; k < 18; k++) {
                    const rx = 7 + k * 2.8 * s, ry = 10 + k * 3.5 * s;
                    g.strokeStyle = `rgba(255,255,255,${(k % 2 ? 0.18 : 0.3) * Math.min(1, a * 1.6)})`; g.lineWidth = 1.5;
                    const a0 = r() * 0.9;
                    g.beginPath(); g.ellipse(0, 0, rx, ry, 0, a0, a0 + 3.8 + r() * 1.8); g.stroke();
                }
                g.restore();
            }
        },
        dirt(g, r, a) {
            const cx = W * (0.15 + r() * 0.35), cy = H * (0.45 + r() * 0.35);
            blob(g, r, cx, cy, 64, `rgba(78,56,28,${0.78 * a})`, 10);
            blob(g, r, cx - 12, cy - 10, 34, `rgba(58,40,20,${0.72 * a})`, 6);
            for (let i = 0; i < 90 * a; i++) {
                g.fillStyle = `rgba(60,45,25,${0.3 + r() * 0.4})`;
                g.beginPath(); g.arc(cx + (r() - 0.5) * 150, cy + (r() - 0.5) * 110, 0.6 + r() * 1.8, 0, 7); g.fill();
            }
        },
        stain(g, r, a) {
            const x = W * (0.55 + r() * 0.3), y = H * (0.55 + r() * 0.3), rad = 48 + r() * 18;
            g.save(); g.filter = 'blur(1.5px)'; g.strokeStyle = `rgba(125,82,35,${0.55 * a})`; g.lineWidth = 5;
            g.beginPath();
            for (let t = 0; t <= 6.35; t += 0.2) { const rr = rad + (r() - 0.5) * 8; g.lineTo(x + Math.cos(t) * rr, y + Math.sin(t) * rr * 0.9); }
            g.closePath(); g.stroke(); g.fillStyle = `rgba(150,105,50,${0.16 * a})`; g.fill(); g.restore();
        },
        scratch(g, r, n) {
            g.lineCap = 'round';
            for (let i = 0; i < n; i++) {
                const x = W * (0.15 + r() * 0.7), y = H * (0.1 + r() * 0.75), l = 40 + r() * 120, a = (r() - 0.5) * 2.4;
                const x2 = x + Math.cos(a) * l, y2 = y + Math.sin(a) * l, mx = (x + x2) / 2 + (r() - 0.5) * 18, my = (y + y2) / 2 + (r() - 0.5) * 18;
                g.strokeStyle = 'rgba(0,0,0,.4)'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(x + 0.8, y + 0.8); g.quadraticCurveTo(mx + 0.8, my + 0.8, x2 + 0.8, y2 + 0.8); g.stroke();
                g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineWidth = 1.3; g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(mx, my, x2, y2); g.stroke();
            }
        },
        print(g, r) {
            const x = W * (0.3 + r() * 0.5);
            g.fillStyle = 'rgba(255,255,255,.2)'; g.fillRect(x, 0, 1.5, H);
            g.fillStyle = 'rgba(0,0,0,.12)'; g.fillRect(x + 1.5, 0, 1, H);
        },
        whiten(g, r, a) {
            for (let i = 0; i < 1000 * a; i++) {
                const side = Math.floor(r() * 4), t = r(), d = Math.pow(Math.abs(r() * 2 - 1), 2) * 7;
                let x, y;
                if (side === 0) { x = t * W; y = d; } else if (side === 1) { x = W - d; y = t * H; } else if (side === 2) { x = t * W; y = H - d; } else { x = d; y = t * H; }
                g.fillStyle = `rgba(250,248,240,${0.4 + r() * 0.55})`; g.fillRect(x, y, 1 + r() * 2, 1 + r() * 2);
            }
        },
        water(g, r) {
            const x = W * (0.1 + r() * 0.3), y = H * (0.7 + r() * 0.25);
            g.save(); g.filter = 'blur(6px)'; g.fillStyle = 'rgba(170,150,95,.24)'; g.beginPath();
            for (let t = 0; t <= 6.35; t += 0.25) { const rr = 110 * (0.75 + r() * 0.35); g.lineTo(x + Math.cos(t) * rr, y + Math.sin(t) * rr * 0.8); }
            g.closePath(); g.fill(); g.filter = 'blur(1px)'; g.strokeStyle = 'rgba(110,85,40,.55)'; g.lineWidth = 3; g.stroke(); g.restore();
        },
    };

    // dinged corners + crease as SVG (crisp at any size)
    function damageSvg(c, r) {
        let s = `<defs><filter id="cfxfz" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/></filter><linearGradient id="cfxcg" x1="1" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fbf8ef"/><stop offset="1" stop-color="#d9d2c0"/></linearGradient>
            <linearGradient id="cfxcr" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="rgba(255,255,255,0)"/><stop offset=".47" stop-color="rgba(255,255,255,.18)"/><stop offset=".5" stop-color="rgba(0,0,0,.28)"/><stop offset=".56" stop-color="rgba(0,0,0,0)"/></linearGradient></defs>`;
        const corners = [[1, 0], [0, 1], [0, 0], [1, 1]]; // top-right first, like real wear
        const cornerAt = i => { const [cx, cy] = corners[i]; return { sx: cx ? -1 : 1, sy: cy ? -1 : 1, X: cx * W, Y: cy * H }; };
        const dings = Math.min(4, c.ding || 0);
        // soft, fuzzy corners (the card's own corner score, before any dings)
        const soft = Math.max(0, 9.8 - (c.cor == null ? 9.8 : c.cor));
        if (soft > 0.1) {
            for (let i = dings; i < 4; i++) {
                const { sx, sy, X, Y } = cornerAt(i);
                const rad = 10 + soft * 16 * (0.7 + r() * 0.6);
                s += `<path d="M${X},${Y + sy * rad * 1.5} Q${X + sx * rad * 0.2},${Y + sy * rad * 0.2} ${X + sx * rad * 1.5},${Y}" fill="none" stroke="rgba(252,250,242,${Math.min(0.95, 0.35 + soft * 0.35)})" stroke-width="${3 + soft * 5}" stroke-linecap="round" filter="url(#cfxfz)"/>`;
            }
        }
        for (let i = 0; i < dings; i++) {
            const { sx, sy, X, Y } = cornerAt(i);
            const k = 1.35 + r() * 0.55;
            const pt = (dx, dy) => `${X + sx * dx * k},${Y + sy * dy * k}`;
            // shadow of the bent corner, the frayed white card stock showing through, and the fold line
            s += `<path d="M${pt(0, 0)} L${pt(84, 0)} Q${pt(44, 40)} ${pt(0, 90)} Z" fill="rgba(0,0,0,.28)" filter="url(#cfxfz)"/>
                <path d="M${pt(0, 0)} L${pt(66, 0)} L${pt(60, 7)} L${pt(55, 5)} L${pt(48, 15)} L${pt(42, 12)} L${pt(36, 24)} L${pt(30, 21)} L${pt(22, 34)} L${pt(16, 31)} L${pt(10, 46)} L${pt(5, 44)} L${pt(0, 64)} Z" fill="url(#cfxcg)"/>
                <path d="M${pt(76, 0)} Q${pt(38, 32)} ${pt(0, 74)}" fill="none" stroke="rgba(0,0,0,.65)" stroke-width="4"/>
                <path d="M${pt(81, 0)} Q${pt(41, 36)} ${pt(0, 80)}" fill="none" stroke="rgba(255,255,255,.7)" stroke-width="2.2"/>`;
        }
        if (c.crease) {
            const x1 = W * (0.05 + r() * 0.1), y1 = H * (0.8 + r() * 0.15), x2 = W * (0.9 + r() * 0.08), y2 = H * (0.3 + r() * 0.2);
            const mx = (x1 + x2) / 2 + (r() - 0.5) * 40, my = (y1 + y2) / 2 + (r() - 0.5) * 40;
            const ang = Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI + 90;
            s += `<g transform="rotate(${ang} ${mx} ${my})"><rect x="${mx - 130}" y="${my - 420}" width="260" height="840" fill="url(#cfxcr)" opacity=".7"/></g>
                <path d="M${x1} ${y1} Q${mx} ${my} ${x2} ${y2}" fill="none" stroke="rgba(0,0,0,.6)" stroke-width="4"/>
                <path d="M${x1 - 2} ${y1 - 3} Q${mx - 2} ${my - 3} ${x2 - 2} ${y2 - 3}" fill="none" stroke="rgba(255,255,255,.9)" stroke-width="2.2"/>`;
        }
        return s;
    }

    // damp warping: the card bows, so light catches it in bands
    function warpSvg(c, r) {
        if (!c.warp) return '';
        const horiz = r() < 0.5;
        const g = horiz ? 'x1="0" y1="0" x2="0" y2="1"' : 'x1="0" y1="0" x2="1" y2="0"';
        return `<defs><linearGradient id="cfxwp" ${g}>
            <stop offset="0" stop-color="rgba(0,0,0,.30)"/><stop offset=".18" stop-color="rgba(255,255,255,.22)"/>
            <stop offset=".45" stop-color="rgba(0,0,0,.05)"/><stop offset=".6" stop-color="rgba(0,0,0,.20)"/>
            <stop offset=".82" stop-color="rgba(255,255,255,.2)"/><stop offset="1" stop-color="rgba(0,0,0,.32)"/></linearGradient></defs>
            <rect x="0" y="0" width="${W}" height="${H}" fill="url(#cfxwp)"/>
            <path d="M${horiz ? `0,${H * 0.03} Q${W / 2},${H * 0.07} ${W},${H * 0.03}` : `${W * 0.03},0 Q${W * 0.08},${H / 2} ${W * 0.03},${H}`}" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="3"/>`;
    }

    const CLEANABLE = ['dust', 'finger', 'dirt', 'stain'];

    // Builds the overlay for a condition table `c`. Returns { el, erase, spray, scratchAt, coverage, redraw }
    function create(c) {
        c = c || {};
        const el = document.createElement('div');
        el.className = 'cfx';
        // sun fading: washes the colour out of the card underneath (backdrop filter) + a pale sun-bleached sheen
        const fadeEl = document.createElement('div');
        fadeEl.className = 'cfx-layer cfx-fade';
        el.appendChild(fadeEl);
        const L = {};
        ['wear', 'dirt', 'stain', 'wet', 'dust', 'finger'].forEach(k => { L[k] = mkCanvas(k); el.appendChild(L[k]); });
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('preserveAspectRatio', 'none'); svg.classList.add('cfx-layer');
        el.appendChild(svg);
        const G = {}; Object.keys(L).forEach(k => { G[k] = L[k].getContext('2d', { willReadFrequently: true }); });
        const seed = c.seed || 1;

        function redraw() {
            Object.values(G).forEach(g => g.clearRect(0, 0, W, H));
            if (c.dust > 0.03) DRAW.dust(G.dust, rng(seed + 11), c.dust);
            if (c.finger > 0.03) DRAW.finger(G.finger, rng(seed + 23), c.finger);
            if (c.dirt > 0.03) DRAW.dirt(G.dirt, rng(seed + 37), c.dirt);
            if (c.stain > 0.03) DRAW.stain(G.stain, rng(seed + 41), c.stain);
            if (c.scratch > 0) DRAW.scratch(G.wear, rng(seed + 53), c.scratch);
            if (c.print) DRAW.print(G.wear, rng(seed + 67));
            // edge wear: whitening from carrying it about, plus the card's own edge score
            const edgeWear = (c.whiten || 0) + Math.max(0, 9.8 - (c.edg == null ? 9.8 : c.edg)) * 0.12;
            if (edgeWear > 0.03) DRAW.whiten(G.wear, rng(seed + 71), Math.min(1, edgeWear));
            if (c.water) DRAW.water(G.wear, rng(seed + 83));
            svg.innerHTML = damageSvg(c, rng(seed + 97)) + warpSvg(c, rng(seed + 109));
            const f = Math.max(0, Math.min(1, c.fade || 0));
            if (f > 0.03) {
                const flt = `saturate(${(1 - f * 0.85).toFixed(2)}) brightness(${(1 + f * 0.18).toFixed(2)}) sepia(${(f * 0.35).toFixed(2)}) contrast(${(1 - f * 0.25).toFixed(2)})`;
                fadeEl.style.backdropFilter = flt; fadeEl.style.webkitBackdropFilter = flt;
                const side = rng(seed + 113)() < 0.5 ? '100deg' : '260deg';   // the side that faced the window
                fadeEl.style.background = `linear-gradient(${side}, rgba(255,250,225,${(f * 0.42).toFixed(2)}), rgba(255,248,220,${(f * 0.16).toFixed(2)}) 70%)`;
                fadeEl.style.display = '';
            } else fadeEl.style.display = 'none';
        }
        redraw();

        function coverage(k) {
            const d = G[k].getImageData(0, 0, W, H).data;
            let s = 0; for (let i = 3; i < d.length; i += 64) s += d[i];
            return s;
        }
        const start = {}; CLEANABLE.forEach(k => { start[k] = coverage(k); });

        // wipe: soft = dust/fingerprint strength, grime = dirt/stain strength, wet = droplets smeared away
        function erase(x, y, rot, soft, grime, wet) {
            const pad = (g, strength, rx, ry) => {
                if (!strength) return;
                g.save(); g.globalCompositeOperation = 'destination-out'; g.translate(x, y); g.rotate(rot || 0); g.scale(1, ry / rx);
                const grd = g.createRadialGradient(0, 0, 6, 0, 0, rx);
                grd.addColorStop(0, `rgba(0,0,0,${strength})`); grd.addColorStop(0.7, `rgba(0,0,0,${strength * 0.5})`); grd.addColorStop(1, 'rgba(0,0,0,0)');
                g.fillStyle = grd; g.beginPath(); g.arc(0, 0, rx, 0, 7); g.fill(); g.restore();
            };
            pad(G.dust, soft, 88, 64); pad(G.finger, soft, 88, 64);
            pad(G.dirt, grime, 82, 60); pad(G.stain, grime, 82, 60);
            pad(G.wet, wet, 82, 60);
        }
        function spray(x, y, sprSeed) {
            const r = rng(sprSeed || 1), g = G.wet;
            for (let i = 0; i < 70; i++) {
                const a = r() * 6.283, d = Math.pow(r(), 0.7) * 64, px = x + Math.cos(a) * d, py = y + Math.sin(a) * d * 0.9;
                const rad = r() < 0.93 ? 1 + r() * 2.2 : 4 + r() * 4;
                g.fillStyle = 'rgba(255,255,255,.10)'; g.beginPath(); g.arc(px, py, rad, 0, 7); g.fill();
                g.strokeStyle = 'rgba(0,0,0,.18)'; g.lineWidth = 1; g.beginPath(); g.arc(px + 0.4, py + 0.4, rad, 0.3, 2.2); g.stroke();
                g.fillStyle = 'rgba(255,255,255,.75)'; g.beginPath(); g.arc(px - rad * 0.35, py - rad * 0.35, Math.max(0.6, rad * 0.28), 0, 7); g.fill();
            }
        }
        function dry(amount) {
            const g = G.wet; g.save(); g.globalCompositeOperation = 'destination-out';
            g.fillStyle = `rgba(0,0,0,${amount || 0.035})`; g.fillRect(0, 0, W, H); g.restore();
        }
        function scratchAt(x, y) {
            const g = G.wear; g.lineCap = 'round';
            g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = 1.4; g.beginPath(); g.moveTo(x - 44, y - 10); g.quadraticCurveTo(x + 1, y + 8, x + 55, y - 3); g.stroke();
            g.strokeStyle = 'rgba(255,255,255,.85)'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(x - 45, y - 11); g.quadraticCurveTo(x, y + 7, x + 54, y - 4); g.stroke();
        }
        // share of each cleanable layer still left (1 = untouched)
        function remaining() {
            const out = {};
            CLEANABLE.forEach(k => { out[k] = start[k] > 0 ? Math.min(1, coverage(k) / start[k]) : 1; });
            return out;
        }
        return { el, erase, spray, dry, scratchAt, remaining, redraw, cond: c };
    }

    // off-centre print: how far (in card pixels, 300px wide) the picture sits off the middle
    function centering(c) {
        const cen = c && c.cen != null ? c.cen : 10;
        const off = Math.max(0, Math.min(5.5, (10 - cen) * 1.6));
        if (off < 0.3) return null;
        const r = rng((c.seed || 1) + 131);
        const dirX = r() < 0.5 ? -1 : 1, mix = 0.35 + r() * 0.65;      // mostly left/right, some top/bottom
        const dx = dirX * off * mix, dy = (r() < 0.5 ? -1 : 1) * off * (1 - mix) * 1.2;
        return { dx, dy };
    }

    window.CondFX = { create, centering, W, H };
})();
