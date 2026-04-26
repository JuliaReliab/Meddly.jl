# TODO — EV+MDD 対応の未解決問題

EV+MDD / EV×MDD 操作を実装しようとしたが，MEDDLY の内部挙動に起因する根本的な問題が複数あることが判明した。以下にまとめる。

---

## 1. EV×MDD (EVTIMES) は INTEGER 範囲の MDD に非対応

### 問題
`meddly_forest_create_ev(dom, MDD, INTEGER, EVTIMES)` を呼ぶと
MEDDLY 内部で `TYPE_MISMATCH` 例外がスローされる。

### 原因
MEDDLY 0.18.x の実装 (`forest.cc`) において，EVTIMES は
**REAL 範囲 + RELATION (MXD)** の組み合わせにのみ対応している。

```cpp
case edge_labeling::EVTIMES:
    if (range_type::REAL != t || !sr) {
        throw error(error::TYPE_MISMATCH, __FILE__, __LINE__);
    }
    return new evmxd_timesreal(d, p);
```

### 対処
EV×MDD (INTEGER, MDD) の利用は不可。EV×MDD が必要な場合は
REAL 範囲・RELATION (MXD) フォレストとして作成すること。

---

## 2. EV+MDD の `ifthenelse` が常に cardinality 0 を返す

### 問題
`ifthenelse(c_gt, ea, ec)` の結果が OMEGA_INFINITY (absent) になる。
期待値は cardinality 2 だが，実際は 0。

### 原因
MEDDLY の EV+MDD 演算（PLUS, MULTIPLY）は **OMEGA_INFINITY を吸収元**として扱う。

- `OMEGA_NORMAL(x) + OMEGA_INFINITY = OMEGA_INFINITY`
- `OMEGA_NORMAL(0) * OMEGA_INFINITY = OMEGA_INFINITY`（非終端ノードで早期終了）

特に `arith_pushdn::evplus_mult::simplifiesToSecondArg` は，B = OMEGA_INFINITY
かつ準簡約フォレストであれば **A の辺値がゼロでも** OMEGA_INFINITY を返す。

```cpp
if (OMEGA_INFINITY == bn) return (!f2->isIdentityReduced());
```

このため，ブール条件 c を EV+MDD にコピーして得られる **密な** c_int と，
**疎な** (OMEGA_INFINITY 背景) の t・e を混在させる
`c_int * t + nc_int * e` 式は正しく動作しない。

> **注:** MT (multi-terminal) 整数フォレストの `ifthenelse` はすでに解決済み。
> `MDDForestBool` 条件の場合は C++ `ite_mt` ternary operation（compute table 付き）、
> `MDDForestInt` 条件の場合は算術フォールバック `c * t + (1-c) * e` を使う。
> 上記の問題は EV+MDD に限定される。

### 必要な対処（未実装）

以下のいずれかのアプローチが必要：

**A. C++ レベルでの専用 EV+MDD ifthenelse 操作**
`meddly_edge_ifthenelse_ev(cond_bool, then_evp, else_evp, result_evp)` を
MEDDLY の DD 構造を直接走査して組み立てる。
OMEGA_INFINITY の伝播を抑制した特殊な MERGE 処理が必要。

**B. EV+MDD 上の条件選択に MEDDLY の MAX を利用する**
OMEGA_INFINITY を `−∞` として扱う MAX 変種があれば
疎な 2 つの EV+MDD を "disjoint union" できる可能性がある。
ただし現在の `evplus_max` も OMEGA_INFINITY を吸収元としているため
そのままでは使えない。

**C. 密な背景に統一する**
t・e をあらかじめ OMEGA_NORMAL(0) 背景（dense）で構築した上で
`c_int * t + nc_int * e` を適用する。
「欠落ミンタームを 0 と区別したい」用途では意味が変わる点に注意。

---

## 3. EV+MDD の cardinality の意味

`Edge(evp_f, 0)` (constant 0) は cardinality 16（全ミンターム存在），
`Edge(evp_f, [1,2], 5)` は cardinality 1（スパース）。
この非対称性はユーザーが混乱しやすい。EV+MDD を公開する際はドキュメント整備が望ましい。

---

## 4. EV+MDD 対応に必要なファイル（将来の実装時）

| ファイル | 追加が必要な内容 |
|---|---|
| `c/meddly_c.h` | `meddly_edge_ifthenelse_ev` の宣言 |
| `c/meddly_c.cpp` | `meddly_edge_ifthenelse_ev` の実装（DD 直接走査・OMEGA_INFINITY 回避） |
| `src/lowlevel.jl` | `_ll_edge_ifthenelse_ev` ccall ラッパー |
| `src/types.jl` | `MDDForestEVPlus <: AbstractForest` など EV+MDD 向け型の追加 |
| `src/highlevel.jl` | EV+MDD 向け `ifthenelse` の特殊パス（`_ifthenelse(c, ::MDDForestEVPlus, t, e)`）|
| `test/runtests.jl` | EV+MDD ifthenelse テストの追加 |

---

## 5. その他 — 将来の改善候補

- **ミンターム反復 API**: `foreach_minterm(f, e, callback)` — DD を走査して
  各ミンタームをコールバックで返す。現状は traversal API で自前実装が必要。
- **JLL アーティファクト**: `libmeddly_c` のビルド済みバイナリを JLL パッケージとして
  配布することで `Pkg.build` 不要にできる。
- **MxD（関係フォレスト）テスト**: `kind = :mxd` は配線済みだが最小限しかテストされていない。
