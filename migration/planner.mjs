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

function $planner_add_zero_r(_x_0) {
  if (_x_0 === 0) {
    return null;
  } else {
    return null;
  }
}

function $planner_add_succ_r(_a_0) {
  if (_a_0 === 0) {
    return null;
  } else {
    return null;
  }
}

function $planner_add_assoc(_a_0) {
  if (_a_0 === 0) {
    return null;
  } else {
    return null;
  }
}

function $planner_add_succ_eq(_c_0, _e_0) {
  return null;
}

function $planner_mval(_m_0) {
  if (_m_0.$ === "One") {
    return 1;
  } else if (_m_0.$ === "Two") {
    return 2;
  } else {
    return 5;
  }
}

function $planner_dval(_d_0) {
  if (_d_0.$ === "D0") {
    return 0;
  } else if (_d_0.$ === "D1") {
    return 1;
  } else if (_d_0.$ === "D2") {
    return 2;
  } else if (_d_0.$ === "D3") {
    return 3;
  } else if (_d_0.$ === "D4") {
    return 4;
  } else if (_d_0.$ === "D5") {
    return 5;
  } else if (_d_0.$ === "D6") {
    return 6;
  } else if (_d_0.$ === "D7") {
    return 7;
  } else if (_d_0.$ === "D8") {
    return 8;
  } else {
    return 9;
  }
}

function $planner_pow10(_k_0) {
  if (_k_0 === 0) {
    return 1;
  } else {
    const _p_0 = (_k_0 - 1);
    const _x_0 = ($planner_pow10(_p_0));
    return nat_chk(10 * _x_0);
  }
}

function $planner_pval(_p_0) {
  const _m_0 = _p_0["mant"];
  const _k_0 = _p_0["exp"];
  const _x_0 = ($planner_mval(_m_0));
  const _x_1 = ($planner_pow10(_k_0));
  return nat_chk(_x_0 * _x_1);
}

function $planner_amount_at(_ds_0, _k_0) {
  if (_ds_0.$ === "Nil") {
    return 0;
  } else {
    const _d_0 = _ds_0["head"];
    const _t_0 = _ds_0["tail"];
    const _x_0 = ($planner_dval(_d_0));
    const _x_1 = ($planner_pow10(_k_0));
    const _x_2 = nat_chk(_x_0 * _x_1);
    const _x_3 = ($planner_amount_at(_t_0, nat_chk(_k_0 + 1)));
    return nat_chk(_x_2 + _x_3);
  }
}

function $planner_amount(_ds_0) {
  return $planner_amount_at(_ds_0, 0);
}

function $planner_digit_mants(_d_0) {
  if (_d_0.$ === "D0") {
    return {$: "Nil"};
  } else if (_d_0.$ === "D1") {
    return {$: "Con", "head": {$: "One"}, "tail": {$: "Nil"}};
  } else if (_d_0.$ === "D2") {
    return {$: "Con", "head": {$: "Two"}, "tail": {$: "Nil"}};
  } else if (_d_0.$ === "D3") {
    return {$: "Con", "head": {$: "One"}, "tail": {$: "Con", "head": {$: "Two"}, "tail": {$: "Nil"}}};
  } else if (_d_0.$ === "D4") {
    return {$: "Con", "head": {$: "Two"}, "tail": {$: "Con", "head": {$: "Two"}, "tail": {$: "Nil"}}};
  } else if (_d_0.$ === "D5") {
    return {$: "Con", "head": {$: "Five"}, "tail": {$: "Nil"}};
  } else if (_d_0.$ === "D6") {
    return {$: "Con", "head": {$: "One"}, "tail": {$: "Con", "head": {$: "Five"}, "tail": {$: "Nil"}}};
  } else if (_d_0.$ === "D7") {
    return {$: "Con", "head": {$: "Two"}, "tail": {$: "Con", "head": {$: "Five"}, "tail": {$: "Nil"}}};
  } else if (_d_0.$ === "D8") {
    return {$: "Con", "head": {$: "One"}, "tail": {$: "Con", "head": {$: "Two"}, "tail": {$: "Con", "head": {$: "Five"}, "tail": {$: "Nil"}}}};
  } else {
    return {$: "Con", "head": {$: "Two"}, "tail": {$: "Con", "head": {$: "Two"}, "tail": {$: "Con", "head": {$: "Five"}, "tail": {$: "Nil"}}}};
  }
}

function $planner_msum(_ms_0) {
  if (_ms_0.$ === "Nil") {
    return 0;
  } else {
    const _m_0 = _ms_0["head"];
    const _t_0 = _ms_0["tail"];
    const _x_0 = ($planner_mval(_m_0));
    const _x_1 = ($planner_msum(_t_0));
    return nat_chk(_x_0 + _x_1);
  }
}

function $planner_put(_ms_0, _k_0, _rest_0) {
  if (_ms_0.$ === "Nil") {
    return _rest_0;
  } else {
    const _m_0 = _ms_0["head"];
    const _t_0 = _ms_0["tail"];
    return {$: "Con", "head": {$: "Piece", "mant": _m_0, "exp": _k_0}, "tail": ($planner_put(_t_0, _k_0, _rest_0))};
  }
}

function $planner_denom_at(_ds_0, _k_0) {
  if (_ds_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _d_0 = _ds_0["head"];
    const _t_0 = _ds_0["tail"];
    return $planner_put(($planner_digit_mants(_d_0)), _k_0, ($planner_denom_at(_t_0, nat_chk(_k_0 + 1))));
  }
}

function $planner_denominate(_ds_0) {
  return $planner_denom_at(_ds_0, 0);
}

function $planner_total(_ps_0) {
  if (_ps_0.$ === "Nil") {
    return 0;
  } else {
    const _p_0 = _ps_0["head"];
    const _t_0 = _ps_0["tail"];
    const _x_0 = ($planner_pval(_p_0));
    const _x_1 = ($planner_total(_t_0));
    return nat_chk(_x_0 + _x_1);
  }
}

function $planner_notes_total(_ns_0) {
  if (_ns_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _ns_0["head"];
    const _v_0 = _t_0["value"];
    const _t_1 = _ns_0["tail"];
    const _x_0 = ($planner_notes_total(_t_1));
    return nat_chk(_v_0 + _x_0);
  }
}

function $planner_outs_total(_os_0) {
  if (_os_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _os_0["head"];
    const _v_0 = _t_0["value"];
    const _t_1 = _os_0["tail"];
    const _x_0 = ($planner_outs_total(_t_1));
    return nat_chk(_v_0 + _x_0);
  }
}

function $planner_zip317_fee(_spends_0, _outputs_0) {
  const _x_0 = (_spends_0 > _outputs_0 ? _spends_0 : _outputs_0);
  const _x_1 = (2 > _x_0 ? 2 : _x_0);
  return nat_chk(5000 * _x_1);
}

function $planner_bool_disc(_b_0) {
  if (!_b_0) {
    return null;
  } else {
    return null;
  }
}

function $planner_false_ne_true(_e_0) {
  return {$: "Unit"};
}

function $planner_sub_add(_h_0, _n_0, _e_0) {
  if (_h_0 === 0) {
    if (_n_0 === 0) {
      return null;
    } else {
      return $Empty_absurd(($planner_false_ne_true(_e_0)));
    }
  } else {
    const _hp_0 = (_h_0 - 1);
    if (_n_0 === 0) {
      return $planner_add_zero_r(nat_chk(_hp_0 + 1));
    } else {
      const _np_1 = (_n_0 - 1);
      return $planner_add_succ_eq((_hp_0 < _np_1 ? 0 : _hp_0 - _np_1), ($planner_sub_add(_hp_0, _np_1, _e_0)));
    }
  }
}

function $planner_split_if(_need_0, _have_0, _b_0) {
  if (_b_0) {
    return {$: "Some", "value": {$: "Change", "change": (_have_0 < _need_0 ? 0 : _have_0 - _need_0)}};
  } else {
    return {$: "None"};
  }
}

function $planner_split(_need_0, _have_0) {
  return $planner_split_if(_need_0, _have_0, ($Nat_is_ge(_have_0, _need_0)));
}

function $planner_mul_distrib(_a_0, _p_0) {
  if (_a_0 === 0) {
    return null;
  } else {
    return null;
  }
}

function $planner_digit_sum(_d_0) {
  if (_d_0.$ === "D0") {
    return null;
  } else if (_d_0.$ === "D1") {
    return null;
  } else if (_d_0.$ === "D2") {
    return null;
  } else if (_d_0.$ === "D3") {
    return null;
  } else if (_d_0.$ === "D4") {
    return null;
  } else if (_d_0.$ === "D5") {
    return null;
  } else if (_d_0.$ === "D6") {
    return null;
  } else if (_d_0.$ === "D7") {
    return null;
  } else if (_d_0.$ === "D8") {
    return null;
  } else {
    return null;
  }
}

function $planner_put_total(_ms_0, _k_0) {
  if (_ms_0.$ === "Nil") {
    return null;
  } else {
    return null;
  }
}

function $planner_conservation_at(_ds_0, _k_0) {
  if (_ds_0.$ === "Nil") {
    return null;
  } else {
    return null;
  }
}

function $planner_to_outputs(_ps_0) {
  if (_ps_0.$ === "Nil") {
    return {$: "Nil"};
  } else {
    const _p_0 = _ps_0["head"];
    const _t_0 = _ps_0["tail"];
    return {$: "Con", "head": {$: "Output", "pool": {$: "Ironwood"}, "value": ($planner_pval(_p_0))}, "tail": ($planner_to_outputs(_t_0))};
  }
}

function $planner_outs_conserve(_ps_0) {
  if (_ps_0.$ === "Nil") {
    return null;
  } else {
    return null;
  }
}

function $planner_AllIronwood(_os_0) {
  if (_os_0.$ === "Nil") {
    return null;
  } else {
    const _t_0 = _os_0["head"];
    return $Pair();
  }
}

function $planner_iron_outs(_ps_0) {
  if (_ps_0.$ === "Nil") {
    return {$: "Unit"};
  } else {
    const _t_0 = _ps_0["tail"];
    return {$: "Tuple", "fst": null, "snd": ($planner_iron_outs(_t_0))};
  }
}

function $planner_IsCanonical(_v_0) {
  return $Exists();
}

function $planner_AllCanon(_os_0) {
  if (_os_0.$ === "Nil") {
    return null;
  } else {
    const _t_0 = _os_0["head"];
    return $Pair();
  }
}

function $planner_canon_outs(_ps_0) {
  if (_ps_0.$ === "Nil") {
    return {$: "Unit"};
  } else {
    const _t_0 = _ps_0["head"];
    const _m_0 = _t_0["mant"];
    const _k_0 = _t_0["exp"];
    const _t_1 = _ps_0["tail"];
    return {$: "Tuple", "fst": {$: "Tuple", "fst": _m_0, "snd": {$: "Tuple", "fst": _k_0, "snd": null}}, "snd": ($planner_canon_outs(_t_1))};
  }
}

function $planner_n_spent(_ns_0) {
  return $List_length(_ns_0);
}

function $planner_n_outputs(_os_0) {
  return $List_length(_os_0);
}

function $planner_balance_of(_c_0, _e_0) {
  return $Equal_sym(_e_0);
}

function $planner_plan_mk(_spent_0, _outs_0, _fee_0, _r_0) {
  if (_r_0.$ === "None") {
    return {$: "None"};
  } else {
    const _t_0 = _r_0["value"];
    const _c_0 = _t_0["change"];
    return {$: "Some", "value": {$: "Plan", "spent": _spent_0, "outputs": _outs_0, "change": _c_0, "fee": _fee_0}};
  }
}

function $planner_plan(_spent_0, _ds_0) {
  const _ps_0 = ($planner_denominate(_ds_0));
  const _outs_0 = ($planner_to_outputs(_ps_0));
  const _fee_0 = ($planner_zip317_fee(($planner_n_spent(_spent_0)), nat_chk(($planner_n_outputs(_outs_0)) + 1)));
  const _x_0 = ($planner_outs_total(_outs_0));
  return $planner_plan_mk(_spent_0, _outs_0, _fee_0, ($planner_split(nat_chk(_x_0 + _fee_0), ($planner_notes_total(_spent_0)))));
}

function $digit_of(_r_0) {
  if (_r_0 === 0) {
    return {$: "D0"};
  } else if (_r_0 === 1) {
    return {$: "D1"};
  } else if (_r_0 === 2) {
    return {$: "D2"};
  } else if (_r_0 === 3) {
    return {$: "D3"};
  } else if (_r_0 === 4) {
    return {$: "D4"};
  } else if (_r_0 === 5) {
    return {$: "D5"};
  } else if (_r_0 === 6) {
    return {$: "D6"};
  } else if (_r_0 === 7) {
    return {$: "D7"};
  } else if (_r_0 === 8) {
    return {$: "D8"};
  } else {
    return {$: "D9"};
  }
}

function $digits_cons(_d_0, _last_0, _rest_0) {
  if (_last_0) {
    return {$: "Con", "head": _d_0, "tail": {$: "Nil"}};
  } else {
    return {$: "Con", "head": _d_0, "tail": _rest_0};
  }
}

function $digits(_fuel_0, _n_0) {
  if (_fuel_0 === 0) {
    return {$: "Nil"};
  } else {
    const _f_0 = (_fuel_0 - 1);
    return $digits_cons(($digit_of(($Nat_mod(_n_0, 10)))), ($Nat_is_eq(($Nat_div(_n_0, 10)), 0)), ($digits(_f_0, ($Nat_div(_n_0, 10)))));
  }
}

function $zec(_z_0) {
  const _x_0 = ($Nat_show(_z_0));
  return (_x_0 + " zat");
}

function $show_outs(_os_0) {
  if (_os_0.$ === "Nil") {
    return "";
  } else {
    const _t_0 = _os_0["head"];
    const _v_0 = _t_0["value"];
    const _t_1 = _os_0["tail"];
    const _x_0 = ($zec(_v_0));
    const _x_1 = ($show_outs(_t_1));
    const _x_2 = (_x_0 + _x_1);
    return ("\n    Ironwood  " + _x_2);
  }
}

function $show_plan(_m_0) {
  if (_m_0.$ === "None") {
    return "  no plan: the notes do not cover amount + fee";
  } else {
    const _t_0 = _m_0["value"];
    const _s_0 = _t_0["spent"];
    const _o_0 = _t_0["outputs"];
    const _c_0 = _t_0["change"];
    const _f_0 = _t_0["fee"];
    const _x_0 = ($zec(_f_0));
    const _x_1 = (_x_0 + " (ZIP 317)");
    const _x_2 = ($zec(_c_0));
    const _x_3 = ("\n  fee      " + _x_1);
    const _x_4 = (_x_2 + _x_3);
    const _x_5 = ($show_outs(_o_0));
    const _x_6 = ("\n  change   Ironwood  " + _x_4);
    const _x_7 = (_x_5 + _x_6);
    const _x_8 = ($Nat_show(($planner_n_outputs(_o_0))));
    const _x_9 = (" denominated outputs:" + _x_7);
    const _x_10 = (_x_8 + _x_9);
    const _x_11 = ("\n  " + _x_10);
    const _x_12 = ($Nat_show(($planner_n_spent(_s_0))));
    const _x_13 = (" Orchard note(s)" + _x_11);
    const _x_14 = (_x_12 + _x_13);
    const _x_15 = ($zec(($planner_notes_total(_s_0))));
    const _x_16 = (" from " + _x_14);
    const _x_17 = (_x_15 + _x_16);
    return ("  spend " + _x_17);
  }
}

function $run(_notes_0, _amount_0) {
  const _x_0 = ($show_plan(($planner_plan(_notes_0, ($digits(20, _amount_0))))));
  const _x_1 = ($zec(_amount_0));
  const _x_2 = (":\n" + _x_0);
  const _x_3 = (_x_1 + _x_2);
  return ("migrate " + _x_3);
}

function $Empty_absurd(_e_0) {
  throw "bend: runtime fail-stop";
}

function $Nat_is_ge(_a_0, _b_0) {
  return $Cmp_is_ge(cmp_new(_a_0, _b_0));
}

function $Pair() {
  return null;
}

function $Exists() {
  return null;
}

function $List_length(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return 0;
  } else {
    const _t_0 = _xs_0["tail"];
    return nat_chk(($List_length(_t_0)) + 1);
  }
}

function $Equal_sym(_e_0) {
  return null;
}

function $Nat_mod(_a_0, _b_0) {
  return $Pair_snd(nat_divmod(_a_0, _b_0));
}

function $Nat_is_eq(_a_0, _b_0) {
  return $Cmp_is_eq(cmp_new(_a_0, _b_0));
}

function $Nat_div(_a_0, _b_0) {
  return $Pair_fst(nat_divmod(_a_0, _b_0));
}

function $Nat_show(_n_0) {
  const _m_0 = _n_0;
  return $Nat_show_fin(_m_0, "", ($Nat_show_put(nat_divmod(_m_0, 10))));
}

function $Cmp_is_ge(_c_0) {
  if (_c_0.$ === "LT") {
    return false;
  } else {
    return true;
  }
}

function $Pair_snd(_p_0) {
  const _b_0 = _p_0["snd"];
  return _b_0;
}

function $Cmp_is_eq(_c_0) {
  if (_c_0.$ === "EQ") {
    return true;
  } else {
    return false;
  }
}

function $Pair_fst(_p_0) {
  const _a_0 = _p_0["fst"];
  return _a_0;
}

function $Nat_show_fin($0, $1, $2) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _dq_0 = $2;
      const _d_0 = _dq_0["fst"];
      const _t_0 = _dq_0["snd"];
      if (_t_0 === 0) {
        return (_d_0 + _acc_0);
      } else {
        const _p_0 = (_t_0 - 1);
        $0 = _g_0;
        $1 = nat_chk(_p_0 + 1);
        $2 = (_d_0 + _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = ($Nat_show_put(nat_divmod(_n_0, 10)));
        $pc = 0; continue;
      }
    }
  }
}

function $Nat_show_put(_qr_0) {
  const _q_0 = _qr_0["fst"];
  const _r_0 = _qr_0["snd"];
  const _x_0 = nat_chk(48 + _r_0);
  return {$: "Tuple", "fst": char_new((_x_0 >>> 0)), "snd": _q_0};
}

function $Nat_show_go($0, $1, $2) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _dq_0 = $2;
      const _d_0 = _dq_0["fst"];
      const _t_0 = _dq_0["snd"];
      if (_t_0 === 0) {
        return (_d_0 + _acc_0);
      } else {
        const _p_0 = (_t_0 - 1);
        $0 = _g_0;
        $1 = nat_chk(_p_0 + 1);
        $2 = (_d_0 + _acc_0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = ($Nat_show_put(nat_divmod(_n_0, 10)));
        $pc = 0; continue;
      }
    }
  }
}
export default {
  "planner:add_zero_r": run_lib((a0) => run_loop($planner_add_zero_r(nat_in(a0))), 1),
  "planner:add_succ_r": run_lib((a0) => run_loop($planner_add_succ_r(nat_in(a0))), 1),
  "planner:add_assoc": run_lib((a0) => run_loop($planner_add_assoc(nat_in(a0))), 1),
  "planner:add_succ_eq": run_lib((a0,a1) => run_loop($planner_add_succ_eq(nat_in(a0),a1)), 2),
  "planner:mval": run_lib((a0) => run_loop($planner_mval(a0)), 1),
  "planner:dval": run_lib((a0) => run_loop($planner_dval(a0)), 1),
  "planner:pow10": run_lib((a0) => run_loop($planner_pow10(nat_in(a0))), 1),
  "planner:pval": run_lib((a0) => run_loop($planner_pval(a0)), 1),
  "planner:amount_at": run_lib((a0,a1) => run_loop($planner_amount_at(a0,nat_in(a1))), 2),
  "planner:amount": run_lib((a0) => run_loop($planner_amount(a0)), 1),
  "planner:digit_mants": run_lib((a0) => run_loop($planner_digit_mants(a0)), 1),
  "planner:msum": run_lib((a0) => run_loop($planner_msum(a0)), 1),
  "planner:put": run_lib((a0,a1,a2) => run_loop($planner_put(a0,nat_in(a1),a2)), 3),
  "planner:denom_at": run_lib((a0,a1) => run_loop($planner_denom_at(a0,nat_in(a1))), 2),
  "planner:denominate": run_lib((a0) => run_loop($planner_denominate(a0)), 1),
  "planner:total": run_lib((a0) => run_loop($planner_total(a0)), 1),
  "planner:notes_total": run_lib((a0) => run_loop($planner_notes_total(a0)), 1),
  "planner:outs_total": run_lib((a0) => run_loop($planner_outs_total(a0)), 1),
  "planner:zip317_fee": run_lib((a0,a1) => run_loop($planner_zip317_fee(nat_in(a0),nat_in(a1))), 2),
  "planner:bool_disc": run_lib((a0) => run_loop($planner_bool_disc(a0)), 1),
  "planner:false_ne_true": run_lib((a0) => run_loop($planner_false_ne_true(a0)), 1),
  "planner:sub_add": run_lib((a0,a1,a2) => run_loop($planner_sub_add(nat_in(a0),nat_in(a1),a2)), 3),
  "planner:split.if": run_lib((a0,a1,a2) => run_loop($planner_split_if(nat_in(a0),nat_in(a1),a2)), 3),
  "planner:split": run_lib((a0,a1) => run_loop($planner_split(nat_in(a0),nat_in(a1))), 2),
  "planner:mul_distrib": run_lib((a0,a1) => run_loop($planner_mul_distrib(nat_in(a0),nat_in(a1))), 2),
  "planner:digit_sum": run_lib((a0) => run_loop($planner_digit_sum(a0)), 1),
  "planner:put_total": run_lib((a0,a1) => run_loop($planner_put_total(a0,nat_in(a1))), 2),
  "planner:conservation_at": run_lib((a0,a1) => run_loop($planner_conservation_at(a0,nat_in(a1))), 2),
  "planner:to_outputs": run_lib((a0) => run_loop($planner_to_outputs(a0)), 1),
  "planner:outs_conserve": run_lib((a0) => run_loop($planner_outs_conserve(a0)), 1),
  "planner:AllIronwood": run_lib((a0) => run_loop($planner_AllIronwood(a0)), 1),
  "planner:iron_outs": run_lib((a0) => run_loop($planner_iron_outs(a0)), 1),
  "planner:IsCanonical": run_lib((a0) => run_loop($planner_IsCanonical(nat_in(a0))), 1),
  "planner:AllCanon": run_lib((a0) => run_loop($planner_AllCanon(a0)), 1),
  "planner:canon_outs": run_lib((a0) => run_loop($planner_canon_outs(a0)), 1),
  "planner:n_spent": run_lib((a0) => run_loop($planner_n_spent(a0)), 1),
  "planner:n_outputs": run_lib((a0) => run_loop($planner_n_outputs(a0)), 1),
  "planner:balance_of": run_lib((a0,a1) => run_loop($planner_balance_of(nat_in(a0),a1)), 2),
  "planner:plan.mk": run_lib((a0,a1,a2,a3) => run_loop($planner_plan_mk(a0,a1,nat_in(a2),a3)), 4),
  "planner:plan": run_lib((a0,a1) => run_loop($planner_plan(a0,a1)), 2),
  "digit_of": run_lib((a0) => run_loop($digit_of(nat_in(a0))), 1),
  "digits.cons": run_lib((a0,a1,a2) => run_loop($digits_cons(a0,a1,a2)), 3),
  "digits": run_lib((a0,a1) => run_loop($digits(nat_in(a0),nat_in(a1))), 2),
  "zec": run_lib((a0) => str_out(run_loop($zec(nat_in(a0)))), 1),
  "show_outs": run_lib((a0) => str_out(run_loop($show_outs(a0))), 1),
  "show_plan": run_lib((a0) => str_out(run_loop($show_plan(a0))), 1),
  "run": run_lib((a0,a1) => str_out(run_loop($run(a0,nat_in(a1)))), 2),
};
