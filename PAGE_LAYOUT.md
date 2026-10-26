# ページ組版層（page）

`Sources/stone_engine/page/` は、stone_engine に足した「ページ組版層」です。EPUB リーダー SMSReader のために作りました。stone_engine と同じく MIT ライセンスです。

`STLabel` / `STTextView` は、1 つの文字列を 1 つの文字サイズで組みます。この層はその上で、書式の混ざった文章を段落ごとに行へ分け、箱・表・段組・回り込みとともに決まった大きさのページに詰め、`CGContext` に描きます。電子書籍のリフロー表示に使うためのものです（SMSReader はこれで次世代パブリッシング研究会『EPUBリーダー表示テスト』のほとんどの項目を表示します）。

既存のファイル（`context` `font` `layout` `parse` `view`）には手を入れていません。そこから使っているのは次のものです。

- 縦組み用字形への置き換え（`STTextVerticalSubstitutionGlyphWithGlyph`、GSUB の vrt2 / vert）
- 約物の分類（`STPunctuation`）
- 禁則の文字表（`STKinsoku`）

## できること

- **組み方向**: 横組み（horizontal-tb）と縦組み（vertical-rl）。
- **書式の混在**: 1 行の中で、書体（明朝・ゴシック・任意のフォント）、大きさ、太字、斜体、色、字間が混ざってよい。足りない字形は、システムの代わりのフォントで補う。異体字セレクタ（IVS）付きの文字は CoreText で 1 字形にする。
- **ルビ**
  - モノルビ・グループルビ。親文字に画像（外字）を含んでもよい。
  - 長いルビは、前後のルビのないかなに、ルビ 1 字分まで掛ける。
  - 縦組みでは右、横組みでは上に置く。
- **圏点**: ゴマ・ドット・円・二重円・三角と、それぞれの白抜き。
- **縦中横**: 横に並べ、1 字の幅に収める。
- **文字の向き**
  - 縦組みでの正立と横転は、UAX #50 の主な範囲で決める。
  - `text-orientation` に当たる upright / sideways で、まとめて変えられる。
- **上付き・下付き**: ベースラインをずらす。
- **線**: 傍線・下線・打ち消し線。縦組みでは over が右、under が左。行にルビや圏点があれば、その外側に引く。
- **背景**: インライン（span）の背景色、ブロックの背景色。
- **画像**: 行の中の画像（外字）と、1 枚だけの画像のブロック（ページに収まるよう縮める・次のページへ送る）。
- **約物の詰め**
  - 「」「 や 。」 のように約物が続くときの半角詰め。
  - 行頭の始め括弧の詰め。
- **行の分け方**
  - 禁則（行頭・行末）。
  - 、。のぶら下げ。
  - 欧文は単語の間でだけ改行する。
  - ……・――・‥ は 2 字の間で分けない。
- **2倍ダーシ**: ―― ── —— は途切れないよう、つなげて描く。
- **ブロック**: 両端揃え（和文のある行は字間と空白に、欧文だけの行は空白に配る）、行頭・中央・行末揃え、最終行の揃え、字下げ（負の値でぶら下げ）、リストの記号を行の外に出す（`outsideMarker`・`markerEdge`。list-style-position: outside）、前後と左右の余白（CSS どおりに相殺し、ページの頭では捨てる）、行の高さ、改ページの前後、空行（`<br/>` だけの段落）、孤立行（orphans・widows）、1 行目だけの書式（::first-line）。
- **箱**（`STBox`、ブロックの列の中の `boxStart` と `boxEnd` で囲む）: 罫（実線・破線・点線・二重線ほか）、角丸、背景色、背景画像（並べ方・大きさ・位置）、線形・放射・繰り返しのグラデーション、影（外・内）、輪郭線、border-image（9 分割）、幅と高さ（固定・最小・最大）、中身から決まる幅（min-content・max-content・fit-content。`intrinsicInline`、組む前に `resolvingIntrinsicSizes` で測る）、中身を中央に寄せる、回転・拡大・移動（中心は指定できる）、合成モード（mix-blend-mode・background-blend-mode）、中身の切り抜き、ページ・段で分かれたときの辺（slice・clone）、改ページ・改段の前後、分割しない（break-inside: avoid）。罫と padding と 1 行目が入らないページ・段の末尾では始めない。
- **行の中の箱**（`STInlineBox`）: inline 要素の padding・罫・地色を、行ごとにその文字の範囲で描く（ルビまで含めて囲める）。
- **表**（`STTable`）: 列の長さは指定（%・pt）と中身から、行の高さはいちばん高いセルに。行の間で改ページする。縦組みでも組める。
- **回り込み**（`.float`）: 画像を行の先頭か末尾に寄せ、横の行を短くする。
- **段組**（`STColumns`）: 段数か段の幅、段間と段間罫、balance（段の長さをそろえる）と auto、段抜き。段の中の改段。このページで割れるが次のページなら収まる段組は、直前の見出しといっしょに次のページへ送る。
- **書字方向の混在**（`STFlow`）: 横組みのページの中の縦組みのブロック（扉など）、その逆。
- **書体**: 本の書体（`STFontFamily.faces`。太字・斜体・unicode-range で face を選ぶ）、等幅、欧文の本物のイタリック体、OpenType の機能（kern・liga・jp90 ほか）。欧文は単語ごとに CoreText で組み、カーニングと合字を効かせる。
- **約物と行分け**: 行頭・行末・隣接の約物の詰め（text-spacing の space-first・trim-start・allow-end ほか）、和欧間・和数間の四分アキ、word-break（keep-all・break-all）、line-break（loose・normal・strict・anywhere）、長い単語を分けるか（overflow-wrap）、欧文のハイフネーション、行頭の始め括弧と行末の句読点のぶら下げ。
- **ルビ（追加）**: 下側のルビ、両側ルビ、ルビの揃え（start・center・space-between・space-around）、3 字以上のグループルビの行分け、圏点の位置（over・under）と約物には付けないこと、ルビの外側の圏点。
- **線（追加）**: 線の種類（実線・二重線・点線・破線・波線）と色、縦組みの傍線の左右（text-underline-position）、文字ごとの位置。
- **画像（追加）**: object-fit・object-position、合成モード、不透明度（opacity は文字・背景・画像の透明度として）。

## 使い方

```swift
import stone_engine

var body = STTextStyle()
body.size = 16
var ruby = body

var section = STSection(blocks: [
    STBlock(inlines: [
        .text("吾輩は", body),
        .ruby(base: [.text("猫", ruby)], ruby: "ねこ", style: ruby),
        .text("である。明治", body),
        .combined("38", body),          // 縦中横
        .text("年。", body),
    ], baseStyle: body),
], writingMode: .vertical)
section.numberBlocks()                  // 各ブロックの、章の文字列での位置

var settings = STReaderSettings()
settings.fontSize = 17
let typesetter = STTypesetter(settings: settings)       // スレッドごとに 1 つ（書体と字形を覚える）
let geometry = STPageGeometry(size: CGSize(width: 420, height: 600), top: 36, left: 28, bottom: 36, right: 28)
let pages = typesetter.paginate(section, geometry: geometry)

// 描く（ほかのスレッドからでもよい）
let image = STPageRenderer.image(pages[0], geometry: geometry, writingMode: .vertical,
                                 settings: settings, scale: 2, boxes: section.boxes, image: { id in nil })

// ページの上の文字の位置（選択・検索・リンク用）
let characters = pages[0].characters(geometry: geometry, writingMode: .vertical)
let rubies = pages[0].rubies
```

各ページは、章の文字列の中で自分がどこからどこまでかを持っています（`STPage.range`、UTF-16 単位）。そのため、文字の大きさを変えて組み直しても、同じ場所を指せます。

## ファイル

| ファイル | 内容 |
| --- | --- |
| `STPageModel.swift` | 文書の形（`STSection` `STBlock` `STInline`）、書式（`STTextStyle` `STBlockStyle`）、箱・表・段組・書字方向の混在（`STBox` `STTable` `STColumns` `STFlow`）、読み手の設定（`STReaderSettings`） |
| `STFontBook.swift` | 書体の選択（本の face・イタリック・OpenType の機能）と字形のキャッシュ、単語ごとの組み、縦組み用字形（上流の GSUB 読みを鍵の中で呼ぶ） |
| `STCharacterClass.swift` | 文字の性質（縦組みでの向き、約物、禁則、ぶら下げ、単語の文字）のキャッシュ |
| `STTypesetter.swift` | 行に分け、詰め、揃え、ページに詰める。箱・表・回り込み・段組・書字方向の混在のレイアウト |
| `STPageRenderer.swift` | `CGContext` に描く（箱・背景・罫・影・グラデーション・行の中の箱・ルビ・圏点・線） |
| `STPageQueries.swift` | ページの上の文字・ルビ・ブロック・画像の位置 |

## 速さ

20,000 字の章（『吾輩は猫である』の冒頭のくり返し）を、420×600pt のページに組む時間を測りました（iPad Air 11 インチのシミュレータ、デバッグビルド）。

| | 縦組み | 横組み |
| --- | --- | --- |
| ページ組版層 | 約 42ms（52 ページ） | 約 49ms |
| 参考: `STLabel.sizeThatFits` | 約 640ms | 約 610ms |

書体（`CTFont`）と字形を、1 回の組版の中でキャッシュしていることによる差です。

## 気をつけること

- `STTypesetter` はスレッドごとに 1 つ使ってください。組んだ `STPage` は変更しないので、複数のスレッドから同時に描けます。
- 上流の縦組み用字形の置き換えは、プロセス全体で 1 つの状態を持っています。この層では鍵（`NSLock`）の中で呼び、結果を自分でもキャッシュしています。
- UAX #50 は主な範囲だけを表にしています。ここにない文字は横転します。
- 表・段組・書字方向の混在・回り込みは、中身のブロックをそのブロックの後ろに並べ、範囲（`end`）で指す形です。本文の位置（`STBlock.offset`）はふつうのブロックと同じように数えます。
- 段組は段の長さを二分探索で求めるので、段組のある章は組むのに時間がかかります（100ms ほど）。
- 箱を描くには、`STPageRenderer` に `boxes`（`STSection.boxes`）を渡してください。
- macOS 向けのビルドは、上流の `main` と同じく通りません（`STContext.swift` などが UIKit を使っているため）。この層そのものは CoreGraphics・CoreText・Foundation だけを使います。
