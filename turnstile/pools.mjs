function word_to_u32(w) {
  let x = 0;
  for (let i = 0; w.$ === "WCon"; i++) {
    x |= Number(w.head) << i;
    w = w.tail;
  }
  return x >>> 0;
}

function u32_to_word(x) {
  let w = {$: "WNil"};
  for (let i = 31; i >= 0; i--) {
    w = {$: "WCon", head: ((x >>> i) & 1) === 1, tail: w};
  }
  return w;
}

function cmp_new(a, b) {
  return {$: a < b ? "LT" : a === b ? "EQ" : "GT"};
}

function nat_divmod(a, b) {
  return b === 0 ? {$: "Tuple", fst: 0, snd: a}
    : {$: "Tuple", fst: Math.trunc(a / b), snd: a % b};
}

function nat_chk(n) {
  if (n > 281474976710655) {
    throw "bend: a Nat past the largest immediate 2^48-1";
  }
  return n;
}

function nat_in(n) {
  if (!Number.isInteger(n) || n < 0 || n > 2 ** 53) {
    throw "bend: expected a Nat host number: an integer from 0 to 2^53";
  }
  return n;
}

function f32_show(x) {
  let s = "nan";
  for (let p = 1; x === x && p <= 9 && f32_round(s) !== x; p += 1) {
    s = String(Number(x.toExponential(p - 1)));
  }
  return (Object.is(x, -0) ? "-0" : s).replace("Infinity", "inf");
}

function f32_bits(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function f32_from_bits(u) {
  return new Float32Array(new Uint32Array([u]).buffer)[0];
}

function f32_read(s) {
  const re = /^[\t\n\v\f\r ]*[+-]?((\d+(?:\.\d*)?|\.\d+)(e[+-]?\d+)?|inf(inity)?|nan)$/i;
  const v = f32_round(s.replace(/inf\w*/i, "Infinity"));
  return re.test(s) ? {$: "Some", value: v} : {$: "None"};
}

const f32_round = function f32_round(s) {
  const d = Number(s);
  const a = Math.abs(d);
  const f = Math.fround(a);
  const g = 2 * a - Math.min(f, 2 ** 128);
  if (g === f || Math.fround(g) !== g || g === Infinity) {
    return Math.sign(d) * f;
  }
  let k = 0;
  while (a * 2 ** k % 1 !== 0) {
    k += 1;
  }
  const [, i, r, e] = /(\d*)\.?(\d*)(?:e([+-]?\d+))?$/i.exec(s);
  const n = Number(e ?? 0) - r.length;
  const x = BigInt(i + r) * 2n ** BigInt(k) * 10n ** BigInt(Math.max(n, 0));
  const y = BigInt(a * 2 ** k) * 10n ** BigInt(Math.max(-n, 0));
  return Math.sign(d) * (x === y || x > y !== g > f ? f : g);
};

const char_new = function char_new(c) {
  return c < 55296 || c >= 57344 && c <= 1114111 ? String.fromCodePoint(c) : String.fromCharCode(56320, c >>> 22, c >>> 11 & 2047, c & 2047);
};

function char_len(s, at = 0) {
  return s[at] === "\uDC00" ? 4 : s.codePointAt(at) > 0xFFFF ? 2 : 1;
}

function char_code(s) {
  return s.length < 4 ? s.codePointAt(0)
    : (s.charCodeAt(1) << 22 | s.charCodeAt(2) << 11 | s.charCodeAt(3)) >>> 0;
}

function string_contains(s, p) {
  // A match must start at a Char boundary, not inside a packed U32 code.
  for (let at = 0; at <= s.length; at += char_len(s, at)) {
    if (s.startsWith(p, at)) {
      return true;
    }
  }
  return false;
}

function str_out(s) {
  return s.replace(/\uDC00[^]{3}/gu, "\uFFFD");
}

function str_in(s) {
  return s.replace(/\p{Cs}/gu, "\uFFFD");
}

// Array
// =====

function array_new(d, v) {
  if (d > 31) {
    throw "bend: an array past the deepest block class 31";
  }
  return Array(2 ** d).fill(v);
}

function array_node(a, b) {
  if (a.length !== b.length) {
    throw "bend: runtime fail-stop";
  }
  return a.concat(b);
}

function array_rmw(a, i, f) {
  const at = i % a.length;
  const old = a[at];
  a[at] = f(old);
  return {$: "Tuple", fst: a, snd: old};
}

// Run
// ===

function run_tail(f, x) {
  return {$: "$JMP", f: f.j?.f === f ? f.j : f, x};
}

function run_clo(j) {
  const f = (x) => run_loop(j(x));
  f.j = j;
  j.f = f;
  return f;
}

function run_loop(r) {
  while (r !== null && typeof r === "object" && r.$ === "$JMP") {
    r = r.f(r.x);
  }
  return r;
}

function run_lib(f, n) {
  return (...a) => a.length < n ? run_lib((...b) => f(...a, ...b), n - a.length)
    : run_loop(f(...a));
}

// Effect
// ======

const $0eff = Object.create(null);

function io_eff(k, run) {
  if (arguments.length > 2) {
    throw new Error("bend: " + k + " takes no need: an effect that waits parks itself");
  }
  if (k in $0eff) {
    throw new Error("bend: two effects register " + k);
  }
  $0eff[k] = run;
}
// Program
// =======

function $Flow_inp(_f_0) {
  const _i_0 = _f_0["inp"];
  return _i_0;
}

function $Flow_out(_f_0) {
  const _o_0 = _f_0["out"];
  return _o_0;
}

function $Pools_t(_p_0) {
  const _t_0 = _p_0["t"];
  return _t_0;
}

function $Pools_sp(_p_0) {
  const _sp_0 = _p_0["sp"];
  return _sp_0;
}

function $Pools_sa(_p_0) {
  const _sa_0 = _p_0["sa"];
  return _sa_0;
}

function $Pools_orc(_p_0) {
  const _orc_0 = _p_0["orc"];
  return _orc_0;
}

function $Pools_iw(_p_0) {
  const _iw_0 = _p_0["iw"];
  return _iw_0;
}

function $Tx_t(_x_0) {
  const _t_0 = _x_0["t"];
  return _t_0;
}

function $Tx_sp(_x_0) {
  const _sp_0 = _x_0["sp"];
  return _sp_0;
}

function $Tx_sa(_x_0) {
  const _sa_0 = _x_0["sa"];
  return _sa_0;
}

function $Tx_orc(_x_0) {
  const _orc_0 = _x_0["orc"];
  return _orc_0;
}

function $Tx_iw(_x_0) {
  const _iw_0 = _x_0["iw"];
  return _iw_0;
}

function $Tx_issue(_x_0) {
  const _issue_0 = _x_0["issue"];
  return _issue_0;
}

function $Tx_burn(_x_0) {
  const _burn_0 = _x_0["burn"];
  return _burn_0;
}

function $Pools_total(_p_0) {
  const _t_0 = _p_0["t"];
  const _sp_0 = _p_0["sp"];
  const _sa_0 = _p_0["sa"];
  const _orc_0 = _p_0["orc"];
  const _iw_0 = _p_0["iw"];
  const _x_0 = nat_chk(_orc_0 + _iw_0);
  const _x_1 = nat_chk(_sa_0 + _x_0);
  const _x_2 = nat_chk(_sp_0 + _x_1);
  return nat_chk(_t_0 + _x_2);
}

function $Tx_ins(_x_0) {
  const _t_0 = _x_0["t"];
  const _sp_0 = _x_0["sp"];
  const _sa_0 = _x_0["sa"];
  const _orc_0 = _x_0["orc"];
  const _iw_0 = _x_0["iw"];
  const _x_1 = ($Flow_inp(_orc_0));
  const _x_2 = ($Flow_inp(_iw_0));
  const _x_3 = ($Flow_inp(_sa_0));
  const _x_4 = nat_chk(_x_1 + _x_2);
  const _x_5 = ($Flow_inp(_sp_0));
  const _x_6 = nat_chk(_x_3 + _x_4);
  const _x_7 = ($Flow_inp(_t_0));
  const _x_8 = nat_chk(_x_5 + _x_6);
  return nat_chk(_x_7 + _x_8);
}

function $Tx_outs(_x_0) {
  const _t_0 = _x_0["t"];
  const _sp_0 = _x_0["sp"];
  const _sa_0 = _x_0["sa"];
  const _orc_0 = _x_0["orc"];
  const _iw_0 = _x_0["iw"];
  const _x_1 = ($Flow_out(_orc_0));
  const _x_2 = ($Flow_out(_iw_0));
  const _x_3 = ($Flow_out(_sa_0));
  const _x_4 = nat_chk(_x_1 + _x_2);
  const _x_5 = ($Flow_out(_sp_0));
  const _x_6 = nat_chk(_x_3 + _x_4);
  const _x_7 = ($Flow_out(_t_0));
  const _x_8 = nat_chk(_x_5 + _x_6);
  return nat_chk(_x_7 + _x_8);
}

function $csub_go(_ok_0, _a_0, _b_0) {
  if (!_ok_0) {
    return {$: "None"};
  } else {
    return {$: "Some", "value": (_a_0 < _b_0 ? 0 : _a_0 - _b_0)};
  }
}

function $csub(_a_0, _b_0) {
  return $csub_go(($Nat_is_le(_b_0, _a_0)), _a_0, _b_0);
}

function $pool_step(_bal_0, _f_0) {
  const _i_0 = _f_0["inp"];
  const _o_0 = _f_0["out"];
  return $csub(nat_chk(_bal_0 + _i_0), _o_0);
}

function $step5(_a_0, _b_0, _c_0, _d_0, _e_0) {
  if (_a_0.$ === "None") {
    return {$: "None"};
  } else {
    const _x1_0 = _a_0["value"];
    if (_b_0.$ === "None") {
      return {$: "None"};
    } else {
      const _x2_0 = _b_0["value"];
      if (_c_0.$ === "None") {
        return {$: "None"};
      } else {
        const _x3_0 = _c_0["value"];
        if (_d_0.$ === "None") {
          return {$: "None"};
        } else {
          const _x4_0 = _d_0["value"];
          if (_e_0.$ === "None") {
            return {$: "None"};
          } else {
            const _x5_0 = _e_0["value"];
            return {$: "Some", "value": {$: "Pools", "t": _x1_0, "sp": _x2_0, "sa": _x3_0, "orc": _x4_0, "iw": _x5_0}};
          }
        }
      }
    }
  }
}

function $step(_s_0, _x_0) {
  const _t_0 = _s_0["t"];
  const _sp_0 = _s_0["sp"];
  const _sa_0 = _s_0["sa"];
  const _orc_0 = _s_0["orc"];
  const _iw_0 = _s_0["iw"];
  const _ft_0 = _x_0["t"];
  const _fsp_0 = _x_0["sp"];
  const _fsa_0 = _x_0["sa"];
  const _forc_0 = _x_0["orc"];
  const _fiw_0 = _x_0["iw"];
  return $step5(($pool_step(_t_0, _ft_0)), ($pool_step(_sp_0, _fsp_0)), ($pool_step(_sa_0, _fsa_0)), ($pool_step(_orc_0, _forc_0)), ($pool_step(_iw_0, _fiw_0)));
}

function $is_zero(_n_0) {
  if (_n_0 === 0) {
    return true;
  } else {
    return false;
  }
}

function $Era_rules(_e_0, _x_0) {
  if (_e_0.$ === "PreNU63") {
    return $Bool_and(($Bool_and(($Bool_and(($is_zero(($Flow_inp(($Tx_sp(_x_0)))))), ($is_zero(($Flow_inp(($Tx_iw(_x_0)))))))), ($is_zero(($Flow_out(($Tx_iw(_x_0)))))))), ($is_zero(($Tx_burn(_x_0)))));
  } else if (_e_0.$ === "NU63") {
    return $Bool_and(($Bool_and(($is_zero(($Flow_inp(($Tx_sp(_x_0)))))), ($is_zero(($Flow_inp(($Tx_orc(_x_0)))))))), ($is_zero(($Tx_burn(_x_0)))));
  } else {
    return $Bool_and(($Bool_and(($is_zero(($Flow_inp(($Tx_sp(_x_0)))))), ($is_zero(($Flow_out(($Tx_sp(_x_0)))))))), ($is_zero(($Flow_inp(($Tx_orc(_x_0)))))));
  }
}

function $balanced(_x_0) {
  const _x_1 = ($Tx_ins(_x_0));
  const _x_2 = ($Tx_burn(_x_0));
  const _x_3 = ($Tx_outs(_x_0));
  const _x_4 = ($Tx_issue(_x_0));
  return $Nat_is_eq(nat_chk(_x_1 + _x_2), nat_chk(_x_3 + _x_4));
}

function $apply_go(_ok_0, _s_0, _x_0) {
  if (!_ok_0) {
    return {$: "None"};
  } else {
    return $step(_s_0, _x_0);
  }
}

function $apply(_e_0, _s_0, _x_0) {
  return $apply_go(($Bool_and(($Era_rules(_e_0, _x_0)), ($balanced(_x_0)))), _s_0, _x_0);
}

function $next(_e_0, _m_0, _x_0) {
  if (_m_0.$ === "None") {
    return {$: "None"};
  } else {
    const _s_0 = _m_0["value"];
    return $apply(_e_0, _s_0, _x_0);
  }
}

function $apply_all($0, $1, $2) {
  for (;;) {
    {
      const _e_0 = $0;
      const _xs_0 = $1;
      const _m_0 = $2;
      if (_xs_0.$ === "Nil") {
        return _m_0;
      } else {
        const _x_0 = _xs_0["head"];
        const _rest_0 = _xs_0["tail"];
        $0 = _e_0;
        $1 = _rest_0;
        $2 = ($next(_e_0, _m_0, _x_0));
        continue;
      }
    }
  }
}

function $Nat_is_le(_a_0, _b_0) {
  return $Cmp_is_le(cmp_new(_a_0, _b_0));
}

function $Bool_and(_a_0, _b_0) {
  if (!_a_0) {
    return false;
  } else {
    return _b_0;
  }
}

function $Nat_is_eq(_a_0, _b_0) {
  return $Cmp_is_eq(cmp_new(_a_0, _b_0));
}

function $Cmp_is_le(_c_0) {
  if (_c_0.$ === "GT") {
    return false;
  } else {
    return true;
  }
}

function $Cmp_is_eq(_c_0) {
  if (_c_0.$ === "EQ") {
    return true;
  } else {
    return false;
  }
}
export default {
  "Flow.inp": run_lib((a0) => run_loop($Flow_inp(a0)), 1),
  "Flow.out": run_lib((a0) => run_loop($Flow_out(a0)), 1),
  "Pools.t": run_lib((a0) => run_loop($Pools_t(a0)), 1),
  "Pools.sp": run_lib((a0) => run_loop($Pools_sp(a0)), 1),
  "Pools.sa": run_lib((a0) => run_loop($Pools_sa(a0)), 1),
  "Pools.orc": run_lib((a0) => run_loop($Pools_orc(a0)), 1),
  "Pools.iw": run_lib((a0) => run_loop($Pools_iw(a0)), 1),
  "Tx.t": run_lib((a0) => run_loop($Tx_t(a0)), 1),
  "Tx.sp": run_lib((a0) => run_loop($Tx_sp(a0)), 1),
  "Tx.sa": run_lib((a0) => run_loop($Tx_sa(a0)), 1),
  "Tx.orc": run_lib((a0) => run_loop($Tx_orc(a0)), 1),
  "Tx.iw": run_lib((a0) => run_loop($Tx_iw(a0)), 1),
  "Tx.issue": run_lib((a0) => run_loop($Tx_issue(a0)), 1),
  "Tx.burn": run_lib((a0) => run_loop($Tx_burn(a0)), 1),
  "Pools.total": run_lib((a0) => run_loop($Pools_total(a0)), 1),
  "Tx.ins": run_lib((a0) => run_loop($Tx_ins(a0)), 1),
  "Tx.outs": run_lib((a0) => run_loop($Tx_outs(a0)), 1),
  "csub.go": run_lib((a0,a1,a2) => run_loop($csub_go(a0,nat_in(a1),nat_in(a2))), 3),
  "csub": run_lib((a0,a1) => run_loop($csub(nat_in(a0),nat_in(a1))), 2),
  "pool_step": run_lib((a0,a1) => run_loop($pool_step(nat_in(a0),a1)), 2),
  "step5": run_lib((a0,a1,a2,a3,a4) => run_loop($step5(a0,a1,a2,a3,a4)), 5),
  "step": run_lib((a0,a1) => run_loop($step(a0,a1)), 2),
  "is_zero": run_lib((a0) => run_loop($is_zero(nat_in(a0))), 1),
  "Era.rules": run_lib((a0,a1) => run_loop($Era_rules(a0,a1)), 2),
  "balanced": run_lib((a0) => run_loop($balanced(a0)), 1),
  "apply.go": run_lib((a0,a1,a2) => run_loop($apply_go(a0,a1,a2)), 3),
  "apply": run_lib((a0,a1,a2) => run_loop($apply(a0,a1,a2)), 3),
  "next": run_lib((a0,a1,a2) => run_loop($next(a0,a1,a2)), 3),
  "apply_all": run_lib((a0,a1,a2) => run_loop($apply_all(a0,a1,a2)), 3),
};
