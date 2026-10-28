import Base
import ./term.bend as T
import ./gen_bt.bend as BT
import ./gen_ba.bend as BA
# The optimised generated verifier computes the same values as the original (opt_gates.py).
#
# One law per function opt_gates.py rewrites, for each of the two generated verifiers
# (bt = orchard_bt, the batch verifier; ba = orchard_ba, the single verifier). gen.py has
# checked that the original and the optimised body perform the same statements in the same
# order (every line that is not straight-line field arithmetic: calls into the transcript,
# points, MSM, the tail call and the result), differing only in which values they pass.
# o_<f>() lists, as terms, the values the ORIGINAL body passes to those statements; n_<f>()
# the values the OPTIMISED body passes, in the same positions (pairs that are the same
# atom on both sides are left out). The law: in Z/p, for every p = 2 + q, every values of
# the atoms (env: parameters, list reads, results of the other calls) and every values of
# the constants K2.. (cs; K0 = 1 and K1 = 0), the two lists are equal, value by value.

law bt_pp_expr_17:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_17()) == T.evs(1n+q, env, cs, BT.n_pp_expr_17()) : +List<Nat>}

law bt_pp_expr_16:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_16()) == T.evs(1n+q, env, cs, BT.n_pp_expr_16()) : +List<Nat>}

law bt_pp_expr_15:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_15()) == T.evs(1n+q, env, cs, BT.n_pp_expr_15()) : +List<Nat>}

law bt_pp_expr_14:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_14()) == T.evs(1n+q, env, cs, BT.n_pp_expr_14()) : +List<Nat>}

law bt_pp_expr_13:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_13()) == T.evs(1n+q, env, cs, BT.n_pp_expr_13()) : +List<Nat>}

law bt_pp_expr_12:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_12()) == T.evs(1n+q, env, cs, BT.n_pp_expr_12()) : +List<Nat>}

law bt_pp_expr_11:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_11()) == T.evs(1n+q, env, cs, BT.n_pp_expr_11()) : +List<Nat>}

law bt_pp_expr_10:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_10()) == T.evs(1n+q, env, cs, BT.n_pp_expr_10()) : +List<Nat>}

law bt_pp_expr_9:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_9()) == T.evs(1n+q, env, cs, BT.n_pp_expr_9()) : +List<Nat>}

law bt_pp_expr_8:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_8()) == T.evs(1n+q, env, cs, BT.n_pp_expr_8()) : +List<Nat>}

law bt_pp_expr_7:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_7()) == T.evs(1n+q, env, cs, BT.n_pp_expr_7()) : +List<Nat>}

law bt_pp_expr_6:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_6()) == T.evs(1n+q, env, cs, BT.n_pp_expr_6()) : +List<Nat>}

law bt_pp_expr_5:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_5()) == T.evs(1n+q, env, cs, BT.n_pp_expr_5()) : +List<Nat>}

law bt_pp_expr_4:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_4()) == T.evs(1n+q, env, cs, BT.n_pp_expr_4()) : +List<Nat>}

law bt_pp_expr_3:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_3()) == T.evs(1n+q, env, cs, BT.n_pp_expr_3()) : +List<Nat>}

law bt_pp_expr_2:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_2()) == T.evs(1n+q, env, cs, BT.n_pp_expr_2()) : +List<Nat>}

law bt_pp_expr_1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr_1()) == T.evs(1n+q, env, cs, BT.n_pp_expr_1()) : +List<Nat>}

law bt_pp_expr:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_expr()) == T.evs(1n+q, env, cs, BT.n_pp_expr()) : +List<Nat>}

law bt_ex_loop:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_ex_loop()) == T.evs(1n+q, env, cs, BT.n_ex_loop()) : +List<Nat>}

law bt_pp_qa:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_pp_qa()) == T.evs(1n+q, env, cs, BT.n_pp_qa()) : +List<Nat>}

law bt_qa_loop:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_qa_loop()) == T.evs(1n+q, env, cs, BT.n_qa_loop()) : +List<Nat>}

law bt_verify_2_part0:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_verify_2_part0()) == T.evs(1n+q, env, cs, BT.n_verify_2_part0()) : +List<Nat>}

law bt_verify_2_part1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_verify_2_part1()) == T.evs(1n+q, env, cs, BT.n_verify_2_part1()) : +List<Nat>}

law bt_verify_1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_verify_1()) == T.evs(1n+q, env, cs, BT.n_verify_1()) : +List<Nat>}

law bt_verify_part0:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_verify_part0()) == T.evs(1n+q, env, cs, BT.n_verify_part0()) : +List<Nat>}

law bt_verify_part1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BT.o_verify_part1()) == T.evs(1n+q, env, cs, BT.n_verify_part1()) : +List<Nat>}

law ba_pp_expr_17:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_17()) == T.evs(1n+q, env, cs, BA.n_pp_expr_17()) : +List<Nat>}

law ba_pp_expr_16:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_16()) == T.evs(1n+q, env, cs, BA.n_pp_expr_16()) : +List<Nat>}

law ba_pp_expr_15:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_15()) == T.evs(1n+q, env, cs, BA.n_pp_expr_15()) : +List<Nat>}

law ba_pp_expr_14:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_14()) == T.evs(1n+q, env, cs, BA.n_pp_expr_14()) : +List<Nat>}

law ba_pp_expr_13:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_13()) == T.evs(1n+q, env, cs, BA.n_pp_expr_13()) : +List<Nat>}

law ba_pp_expr_12:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_12()) == T.evs(1n+q, env, cs, BA.n_pp_expr_12()) : +List<Nat>}

law ba_pp_expr_11:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_11()) == T.evs(1n+q, env, cs, BA.n_pp_expr_11()) : +List<Nat>}

law ba_pp_expr_10:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_10()) == T.evs(1n+q, env, cs, BA.n_pp_expr_10()) : +List<Nat>}

law ba_pp_expr_9:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_9()) == T.evs(1n+q, env, cs, BA.n_pp_expr_9()) : +List<Nat>}

law ba_pp_expr_8:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_8()) == T.evs(1n+q, env, cs, BA.n_pp_expr_8()) : +List<Nat>}

law ba_pp_expr_7:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_7()) == T.evs(1n+q, env, cs, BA.n_pp_expr_7()) : +List<Nat>}

law ba_pp_expr_6:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_6()) == T.evs(1n+q, env, cs, BA.n_pp_expr_6()) : +List<Nat>}

law ba_pp_expr_5:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_5()) == T.evs(1n+q, env, cs, BA.n_pp_expr_5()) : +List<Nat>}

law ba_pp_expr_4:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_4()) == T.evs(1n+q, env, cs, BA.n_pp_expr_4()) : +List<Nat>}

law ba_pp_expr_3:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_3()) == T.evs(1n+q, env, cs, BA.n_pp_expr_3()) : +List<Nat>}

law ba_pp_expr_2:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_2()) == T.evs(1n+q, env, cs, BA.n_pp_expr_2()) : +List<Nat>}

law ba_pp_expr_1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr_1()) == T.evs(1n+q, env, cs, BA.n_pp_expr_1()) : +List<Nat>}

law ba_pp_expr:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_expr()) == T.evs(1n+q, env, cs, BA.n_pp_expr()) : +List<Nat>}

law ba_ex_loop:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_ex_loop()) == T.evs(1n+q, env, cs, BA.n_ex_loop()) : +List<Nat>}

law ba_pp_qa:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_pp_qa()) == T.evs(1n+q, env, cs, BA.n_pp_qa()) : +List<Nat>}

law ba_qa_loop:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_qa_loop()) == T.evs(1n+q, env, cs, BA.n_qa_loop()) : +List<Nat>}

law ba_verify_2_part0:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part0()) == T.evs(1n+q, env, cs, BA.n_verify_2_part0()) : +List<Nat>}

law ba_verify_2_part1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part1()) == T.evs(1n+q, env, cs, BA.n_verify_2_part1()) : +List<Nat>}

law ba_verify_2_part2:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part2()) == T.evs(1n+q, env, cs, BA.n_verify_2_part2()) : +List<Nat>}

law ba_verify_2_part3:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part3()) == T.evs(1n+q, env, cs, BA.n_verify_2_part3()) : +List<Nat>}

law ba_verify_2_part4:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part4()) == T.evs(1n+q, env, cs, BA.n_verify_2_part4()) : +List<Nat>}

law ba_verify_2_part5:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_2_part5()) == T.evs(1n+q, env, cs, BA.n_verify_2_part5()) : +List<Nat>}

law ba_verify_1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_1()) == T.evs(1n+q, env, cs, BA.n_verify_1()) : +List<Nat>}

law ba_verify_part0:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_part0()) == T.evs(1n+q, env, cs, BA.n_verify_part0()) : +List<Nat>}

law ba_verify_part1:
  for +q: Nat
  for +env: +List<Nat>
  for +cs: +List<Nat>
  {T.evs(1n+q, env, cs, BA.o_verify_part1()) == T.evs(1n+q, env, cs, BA.n_verify_part1()) : +List<Nat>}
