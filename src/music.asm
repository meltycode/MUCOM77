;utf-8:tab4
;
; MUCOM88 for FUJITSU FM-7 series with OPN(*2).
;
; based on mucom88em ver. 1.01
; https://github.com/MUCOM88/mucom88
; MUCOM88 refferences
; https://github.com/onitama/mucom88/wiki
;
; how to build.
;> asw -U -cpu 6809 -g map music.asm
;> p2bin music.p -k -l 0 -r $-$

	relaxed	on

	org		$1000

;曲バイナリは $2800- 配置とする（暫定）
;MUCOM88 フォーマットについては以下
;https://docs.google.com/spreadsheets/d/e/2PACX-1vTi1AGJpc8IQhcwAgbm8m0XBgYxRaNXaCs4ZvrNUnz-GMyiDWnU7A3mMTr_h4boEcl2NHy8zfkZPW3q/pubhtml

MUSICNUM	EQU	$2800			;[0]バイナリに含まれる曲データの数-1
OTODAT		EQU	MUSICNUM + 1	;[0][1]FM音源データ部オフセット [2][3]バイナリ全体サイズ
MU_TOP		EQU	MUSICNUM + 5	;曲データ部
MAXCH		EQU	11				;総チャンネル数
PCMADR		EQU	$E300			;ADPCM 情報テーブル（仮）
WKLENG		EQU	CH2DAT - CH1DAT	;1チャンネル分のワークエリアの長さ(38bytes)

;------------------------------------------------------------------------------

	jmp		MSTART						; 演奏開始 a=曲番号(0-)
	jmp		MSTOP						; 演奏停止、FM 音源割込み停止
	jmp		>$0000						; EFECT ENTRY
	jmp		PUTWK						; レジスタバッファに書き込み
	jmp		ESC_PRC						; ESC/CTRL キーによる一時停止・再開処理
	jmp		TSC							; 曲がループしたら T_FLAG を降ろす

	jmp		START						; 演奏開始
	jmp		WORKINIT					; ワークエリア初期化
	jmp		AKYOFF						; 全 FM チャンネルキーオフ
	jmp		SSGOFF						; 全 PSG チャンネル消音
	jmp		MONO						; LR, HWLFO 設定
	jmp		DRIVE						; 全パート処理
	jmp		TO_NML						; 通常モード（非効果音モード）に切り替え
	jmp		PSGOUT						; FM/PSG/RHYTHM レジスタ書き込み
	jmp		WKGET						; 各パートのワークアドレスを u で返す
	jmp		STVOL						; FM 音源の音量設定
	jmp		ENBL						; 音源割込み許可
	jmp		TIME0						; T_FLAG が立っていれば時間を表示する
	jmp		INFADR						; NOTSB2 のアドレスを u で返す

;------------------------------------------------------------------------------
;ESC キーが押されたらフェードアウト
FDOUT:
	ldx		#FDCO
	dec		1,x							;フェードアウトカウンタ（小数）
	bne		.exit
	lda		#$10
	sta		1,x

	lda		,x							;フェードアウトカウンタ（整数）
	beq		.exit
	deca
	sta		,x
;.FDO2:
	adda	#$F0
	sta		TOTALV						;マスターボリューム

	clr		FMPORT						;FM1-3
	ldu		#CH1DAT
	bsr		.FDOFM						;FM1-3 を処理

.FDOSSG:
	ldb		$06,u						;音量
	andb	#%11110000
	lda		$06,u
	anda	#%00001111
	stb		$06,u						;上位 4bit（ソフトエンベロープフラグ） はマスクして書き戻しておく
	lbsr	PSGVOL.PV1					;PSG を処理 a=音量

	leau	WKLENG,u
	cmpu	#CH1DAT + WKLENG * 6
	bne		.FDOSSG

	lbsr	DVOLSET						;リズム音源を処理

	lda		#$04
	sta		FMPORT						;FM4-6
	ldu		#CH1DAT + WKLENG * 7
	bsr		.FDOFM						;FM4-6 を処理

	tst		FDCO						;フェードアウトカウンタ（整数）
	beq		.FDO3
	rts

.FDOFM:
.FDL2:
	lbsr	STVOL						;FM 音源音量設定
	leau	WKLENG,u
	cmpu	#CH1DAT + WKLENG * 3
	beq		.exit
	cmpu	#CH1DAT + WKLENG * 10
	bne		.FDL2
	rts
.FDO3:
	bsr		MSTOP						;演奏停止、FM 音源割込み停止
	clr		TOTALV						;マスターボリューム
.exit:
	rts

;------------------------------------------------------------------------------
;演奏開始
;a=曲番号 (0-)
MSTART:
	lbsr	FM7CHK						;[FM7]
	orcc	#%01010000					;FIRQマスク=1 IRQマスク=1

	sta		MUSICNUM					;曲リクエスト番号を格納
	lbsr	AKYOFF						;全 FM1-6 チャンネルキーオフ
	lbsr	SSGOFF						;全 PSG1-3 チャンネル消音
	lbsr	WORKINIT					;ワークエリア初期化
START:
;	lbsr	CHK							;SB2 存在チェック NOTSB2=0:存在 0以外:不在
	lbsr	INT57						;割込みベクタ設定
	lbsr	ENBL						;FM 音源割込み始動
	lbsr	TO_NML						;FM ch.3 ノーマル／効果音モード切替

	andcc	#%10101111					;FIRQマスク=1 IRQマスク=1
.loop:
	tst		READY
	beq		.exit
	bra		.loop						;[FM7] 暫定
.exit
	orcc	#%01010000					;FIRQマスク=1 IRQマスク=1
	lbsr	MSTOP

	ldd		FM7_IRQSTACK
	std		$FFF8
	ldd		FM7_FIRQSTACK
	std		$FFF6

	andcc	#%10101111					;FIRQマスク=1 IRQマスク=1
	rts

;------------------------------------------------------------------------------
;演奏停止
;FM 音源割込み停止
MSTOP:
	lbsr	AKYOFF						;全 FM1-6 チャンネルキーオフ
	lbsr	SSGOFF						;全 PSG1-3 チャンネル消音

;	lda		M_VECTR
	clr		FM7_IRQMSK					;FM7 Port$32(PC88)の代用 0:disable 8=enable
	rts

;------------------------------------------------------------------------------
;割込みベクタ設定
;
INT57:
	pshs	a,b,x,u

	ldd		#FM7KEY						;[FM7] BREAK キーで演奏停止
	std		$FFF6						;FIRQ 割込みベクタテーブル

	ldd		#PL_SND						;[FM7] IRQ/FM 音源Timer-B 割込み処理
	std		$FFF8						;IRQ 割込みベクタテーブル

	lbsr	TO_NML						;FM ch.3 通常モードにする
;INT573:
	bsr		MONO						;チャンネル定位設定

	lbsr	AKYOFF						;全 FM1-6 チャンネルキーオフ
	lbsr	SSGOFF						;全 PSG1-3 チャンネル消音

	ldd		#$2983						;FM4-6 Enable
	lbsr	PSGOUT

	clra
	clrb
.INITF2:
	lbsr	PSGOUT						;PSG CT/FT をリセット
	inca
	cmpa	#$06
	bne		.INITF2

	ldd		#$0738
	lbsr	PSGOUT						;PSG ミキサをリセット

	ldx		#INITPM						;PSG レジスタ初期値テーブル
	ldu		#PREGBF						;PSG レジスタバッファ
	ldb		#$09 - 1
.loop:
	lda		b,x
	sta		b,u
	decb
	bpl		.loop

	puls	a,b,x,u
	rts

;------------------------------------------------------------------------------
;FM 音源割込み始動
ENBL:
;	lda		M_VECTR
	lda		#$08						;Enable
	sta		FM7_IRQMSK					;[FM7] Port$32(PC88)の代用 0:disable 8=enable

	ldb		TIMER_B
	lbsr	STTMB						;Timer-B 設定と始動 b=引数
	rts

;------------------------------------------------------------------------------
;チャンネル定位設定
;HW LFO を OFF にする
MONO:
	clr		FMPORT
	ldd		#$B4C0						;FM1-3 $B4-$B6
.MONO2:
	lbsr	PSGOUT						;bit76:LR bit54:AMS bit210:PMS
	inca
	cmpa	#$B7
	bne		.MONO2

	lda		#$18
.MONO3:
	lbsr	PSGOUT						;$18-$1D リズム音源 bit76:LR bit4-0:volume
	inca
	cmpa	#$1E
	bne		.MONO3

	lda		#$04
	sta		FMPORT

	lda		#$B4						;FM4-6 $B4-$B6
.MONO4:
	lbsr	PSGOUT
	inca
	cmpa	#$B7
	bne		.MONO4

	clr		FMPORT

	ldd		#$2200						;$22 bit3:1=LFO_ON bit2-0:LFO_FRQ
	lbsr	PSGOUT
;	ldd		#$1200						;$12 LSI_TEST これいらんやろ…
;	lbsr	PSGOUT

	ldy		#PALDAT						;PMS/AMS/LR DATA
	lda		#$C0
	ldb		#$07 - 1
.MONO5:
	sta		b,y
	decb
	bpl		.MONO5

	lda		#$03
	sta		PCMLR						;PCM ステレオ出力
	rts

;------------------------------------------------------------------------------
;IRQ / FM 音源タイマー割込み処理
PL_SND:
	lda		$FD03						;割込み(IRQ)フラグ。bit3:拡張 bit2:TIMER bit1:プリンタ bit0=KEY
	coma								;該当 bit=0:割込みあり。拡張には OPN Timer が接続されている。
	anda	FM7_IRQMSK					;IRQ だけで 4 つの割込み元を持つので、各bitでどの割込みが入ったかを判定する。
	beq		.exit

.PLSET1:
	ldb		#$2A						;ここ書き換え
	lda		#$27						;$2A=通常/$6A=効果音モード用 Timer-On
	lbsr	PSGOUT

;	CTRL+F1 キーで 5 倍速
;	bra		.CUE

;	ESC キーで一旦停止
;	lbsr	ESC_PRC						;ESC の押下チェック
;PL_SND1:
;	tst		ESCAPE						;$F320+$20 ESC によってトグル動作 $00<->$FF
;	bne		.PLSND3

	bsr		DRIVE						;音源ドライバ処理
	lbsr	FDOUT						;フェードアウト処理
;	lbsr	TSC
.PLSND3:

.exit:
	rti

.CUE:
	bsr		DRIVE
	bsr		DRIVE
	bsr		DRIVE
	bsr		DRIVE
	bra		PL_SND.PLSND3

;------------------------------------------------------------------------------
;音源ドライバ処理
DRIVE:
	clr		FMPORT

	ldu		#CH1DAT						;FM1
	bsr		FMENT
	ldu		#CH2DAT						;FM2
	bsr		FMENT
	ldu		#CH3DAT						;FM3
	bsr		FMENT

	lda		#$FF
	sta		SSGF1

	ldu		#CH4DAT						;PSG1
	bsr		SSGENT
	ldu		#CH5DAT						;PSG2
	bsr		SSGENT
	ldu		#CH6DAT						;PSG3
	bsr		SSGENT

	clr		SSGF1

	tst		NOTSB2
	bne		.exit

	lda		#$01
	sta		DRMF1

	ldu		#DRAMDAT
	bsr		FMENT

	clr		DRMF1						;リズム音源

	lda		#$04
	sta		FMPORT

	ldu		#CHADAT						;FM4
	bsr		FMENT
	ldu		#CHBDAT						;FM5
	bsr		FMENT
	ldu		#CHCDAT						;FM6
	bsr		FMENT

	lda		#$FF
	sta		PCMFLG

	ldu		#PCMDAT						;ADPCM
	bsr		FMENT

	clr		PCMFLG
.exit:
	rts

;------------------------------------------------------------------------------
;PSG パート処理
SSGENT:
	lda		$1F,u
	bita	#%00001000					;mute flag
	beq		.skip
	bsr		REOFF						;ミュート有効
.skip:
	lbsr	SSGSUB						;コマンド処理
	lbsr	PLLFO						;LFO 処理

	lda		$1F,u
	bita	#%00001000					;mute flag
	beq		.exit
	bsr		REON						;ミュート無効
.exit:
	rts

;------------------------------------------------------------------------------
;FM/Rhythm/ADPCM パート処理
FMENT:
	lda		$1F,u
	bita	#%00001000					;mute flag
	beq		.skip
	bsr		REOFF						;ミュート有効
.skip:
	bsr		FMSUB						;コマンド処理
	lbsr	PLLFO						;LFO 処理

	lda		$1F,u
	bita	#%00001000					;mute flag
	beq		.exit
	bsr		REON						;ミュート無効
.exit:
	rts

;------------------------------------------------------------------------------
;ミュート 有効/無効切替
REON:
	lda		#$FF
	sta		READY
	rts

REOFF:
	clra
	sta		READY
	rts

;------------------------------------------------------------------------------
;FM 音源コマンド処理
FMSUB:
	dec		,u							;音長デクリメント
	beq		.FMSUB1

	lda		,u
	cmpa	$12,u						;q 値
	bne		.exit

;.FMSUB0:
	ldx		$02,u						;シーケンスポインタ
	lda		,x							;1byte 読む
	cmpa	#$FD
	beq		.exit						;続くコマンドが $FD=タイなら q 効果なし

	lda		$21,u
	bita	#%00100000					;reverb flag
	bne		.FS2
	lbsr	KEYOFF						;リバーブフラグがオフなら q のタイミングでキーオフする
.exit:
	rts

.FS2:
	ldb		$06,u						;音量
	addb	$11,u						;リバーブパラメータと足して半分にする
	lsrb
	lbsr	STVOL.STV2					;FM 音源音量設定。b=引数
	lda		$1F,u
	ora		#%01000000					;Set keyoff flag
	sta		$1F,u
	rts

.FMSUB1:								;音長満期で次の 1byte を読む
	lda		$1F,u
	ora		#%01000000					;Set keyoff flag
	sta		$1F,u

	ldx		$02,u						;シーケンスポインタ
	lda		,x							;1byte 読む
	cmpa	#$FD						;続くコマンドが $FD=タイなら
	bne		.FMSUBC
;.FMSUBE:
	lda		$1F,u
	anda	#%10111111					;Reset keyoff flag キーオフせず音長を続行
	sta		$1F,u
	leax	1,x

.FMSUBC:								;*** ここはコマンド処理後の rts 先としてスタックに積まれる ***
	lda		,x
	bne		.FMSUB2

	lda		$1F,u						;$00 なら
	ora		#%00000001					;1loop end flag
	sta		$1F,u

	ldd		$04,u						;ループ先取得
	lbeq	FMEND						;0ならループせず曲終了

	tfr		d,x
;.FMSUBB:
	lda		,x							;新規コマンド

.FMSUB2:
	leax	1,x							;ポインタインクリメント
	cmpa	#$F0
	lbcc	FMSUBA						;$F0-$FF はコマンド

	tfr		a,b
	anda	#%01111111
	sta		,u							;bit0-6 を音長として格納
	tstb								;bit7 は休符フラグ
	bpl		.FMSUB5

;.FMSUB3:
	stx		$02,u						;ポインタ更新
	lda		$21,u
	bita	#%00010000					;リバーブモード
	bne		.FS3
	bita	#%00100000					;リバーブフラグ
	bne		.FS2
.FS3:
	lbsr	KEYOFF
	rts

.FMSUB5:
	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	beq		.skip
	lbsr	KEYOFF
.skip:
	lda		PL_SND.PLSET1+1
	cmpa	#$6A						;現在ノーマルモード($2A)か効果音モード($6A)かをチェック
	bne		.FMSUB4

	tst		FMPORT
	bne		.FMSUB4						;FM1-3 で、かつ
	lda		$08,u						;チャンネル番号が
	cmpa	#$02						;ch.3 なら EXMODE へ
	lbeq	EXMODE

.FMSUB4:
	ldb		,x+
	stx		$02,u						;ポインタ更新

	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	bne		.FMSUB9

	cmpb	$20,u						;ひとつ前のキーコードと同じなら新規にキーオンはしない
	bne		.FMSUB9						;c&c のような状態
	coma								;cf=1 キーオンなし
	rts

.FMSUB9:
	stb		$20,u						;ひとつ前のキーコードを更新

	tst		PCMFLG
	bne		PCMGFQ						;現在 PCM チャンネルなら PCMGFQ へ
	tst		DRMF1
	beq		FMGFQ						;現在リズムチャンネルなら DRMFQ へ

;------------------------------------------------------------------------------
DRMFQ:
	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	beq		.exit
	lbsr	DKEYON						;リズム音源のキーオン処理
.exit:
	rts

;------------------------------------------------------------------------------
;b=キーコード
PCMGFQ:
	pshs	b
	andb	#%00001111					;音程キーコード
	aslb
	ldy		#PCMNMB						;再生サンプリングレートのテーブル
	ldd		b,y
	addd	$09,u						;detune

	lsr		,s							;上位 4bit がオクターブなので >>4 する
	lsr		,s
	lsr		,s
	lsr		,s
	beq		.ASUB72

.ASUB7:
	lsra
	rorb								;d >>= 1 オクターブ毎に音程値を半分にする
	dec		,s
	bne		.ASUB7
.ASUB72:
	std		DELT_N						;ADPCM 再生速度
	puls	b
	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	bne		.AS72
	lbsr	LFORST						;LFO ディレイ再設定
.AS72:
	lbsr	LFORST2						;LFO ピーク・変化量再設定
	lbsr	PLAY						;ADPCM 再生
	rts

;------------------------------------------------------------------------------
;b=キーコード
FMGFQ:
	tfr		b,a							;bit4-6 がオクターブ
	andb	#%01110000
	lsrb								;bit3-5 にシフトで blk

	pshs	b
	anda	#$0F						;bit0-3 が音階
	asla
	ldy		#FNUMB
	ldd		a,y							;fnum をテーブルから引く
	ora		,s							;blk と合体

	addd	$09,u						;detune と加算
	tfr		d,x
	puls	b
	lda		$21,u
	bita	#%01000000					;トレモロフラグ
	bne		.FMS92

	stx		$1D,u						;blk/fnum 保存(ch別)
	stx		FNUM
.FMS92:
	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	beq		.skip
	lbsr	LFORST						;LFO ディレイ再設定
.skip:
	lbsr	LFORST2						;LFO ピーク・変化量再設定

.FMSUB8:
	ldd		#$0000						;ここ書き換え $CC aa bb
.FMSUB6:
	leax	d,x
	pshs	x
.FPORT:
	lda		#$A4						;ここ書き換え $86 nn
	adda	$08,u						;チャンネル番号
	ldb		,s
	lbsr	PSGOUT						;b=blk/fnum.h

	suba	#$04
	ldb		1,s
;FMSUB7:
	lbsr	PSGOUT						;b=fnum.l
	bsr		KEYON
	puls	d
	clra								;cf=0 キーオン済み
	rts

;------------------------------------------------------------------------------
;効果音モード
EXMODE:
	ldb		DETDAT						;op1 について処理
	clra
	std		FMGFQ.FMSUB8+1
	lbsr	FMSUB.FMSUB4
	bcc		.skip						;cf=0:キーオンした 1:キーオンしていない
	rts
.skip:
	ldy		#DETDAT+1					;op2-4 について処理
	lda		#$AA
	sta		FMGFQ.FPORT+1				;ch=2 を足すので $AC,$AD,$AE になる
.EXMLP:
	ldb		,y+
	clra
;HLSTC0:
	ldx		FNUM
	bsr		FMGFQ.FMSUB6				;x+=d

	inc		FMGFQ.FPORT+1
	lda		FMGFQ.FPORT+1
	cmpa	#$AD						;cmpy #DETDAT+4 でいいか…
	bne		.EXMLP

	lda		#$A4
	sta		FMGFQ.FPORT+1				;元に戻す
;BRESET:
	ldd		#$0000
	std		FMGFQ.FMSUB8+1				;元に戻す
	rts

;------------------------------------------------------------------------------
;FM/ADPCM/RHYTHM キーオフ
KEYOFF:
	tst		PCMFLG
	lbne	PCMEND						;PCM チャンネルは PCMEND へ
	tst		DRMF1
	bne		DKEYOF						;リズムチャンネルは DKEYOF へ

	ldb		FMPORT
	addb	$08,u						;チャンネル番号
	lda		#$28						;レジスタ $28
	bsr		PSGOUT
	rts

;------------------------------------------------------------------------------
;リズム音源キーオフ
DKEYOF:
	lda		#$10						;レジスタ $10
	ldb		RHYTHM
	andb	#%00111111					;選択音色をマスク
	orb		#%10000000					;ダンプ
	bsr		PSGOUT
	rts

;------------------------------------------------------------------------------
;FM 音源キーオン
KEYON:
	tst		READY
	beq		.exit

	ldb		#$F0						;FM1-3
	tst		FMPORT
	beq		.KEYON2						;addb FMPORT4 でも良い
	ldb		#$F4						;FM4-6
.KEYON2:
	addb	$08,u						;チャンネル番号
	lda		#$28						;レジスタ $28
	bsr		PSGOUT

	lda		$21,u
	bita	#%00100000					;リバーブフラグ
	beq		.exit
	lbsr	STVOL
.exit:
	rts

;------------------------------------------------------------------------------
;リズム音源キーオン
DKEYON:
	tst		READY
	beq		.exit
	lda		#$10						;レジスタ $10
	ldb		RHYTHM
	andb	#%00111111					;選択音色をマスク
	bsr		PSGOUT						;bit7=0 で KEY ON
.exit
	rts

;------------------------------------------------------------------------------
;全 FM チャンネルキーオフ
AKYOFF:
	pshs	a,b

	clr		FMPORT
	ldd		#$2800
	bsr		.AKYOF2

	lda		#$04
	sta		FMPORT
	ldd		#$2800
	bsr		.AKYOF2

	clr		FMPORT
	puls	a,b
	rts

.AKYOF2:
	bsr		PSGOUT
	incb
	cmpb	#$03
	bne		.AKYOF2
	rts

;------------------------------------------------------------------------------
;FM, PSG, リズム音源書き込み
;a=reg b=data
PSGOUT:
	pshs	a,x
	ldx		#$FD15						;PORT13 相当

	cmpa	#$28
	beq		.skip						;[FM7] WHG 側キーオンを場合分けする必要がある
	cmpa	#$30
	bcs		.PSGO4						;reg<$30 は PSG or リズム音源, reg>=$30 は FM 音源
.skip:
	tst		FMPORT
	beq		.PSGO4						;reg>=$30 で FMPORT!=0 なら FM4-6

	ldx		#$FD45						;PORT13+1 相当の OPNA FM4-6 側 I/O ポート（仮想）

.PSGO4:
;	lda		#$04						;リズム音源以外で busy 明けを待つ必要があるとは思えない…
;	sta		,x
;	lda		1,x
;	clr		,x
;	tsta
;	bmi		.PSGO4
;	lda		,s

	sta		$01,x						;$FD16 opn レジスタ書き込み
	lda		#$03						;3=レジスタラッチ
	sta		,x
	clr		,x

	nop									;一応ウェイト
	nop
	nop

	stb		$01,x						;$FD16 opn データ書き込み
	deca								;2=データ書き込み
	sta		,x
	clr		,x

;	bsr		PUTWK						;省略

	puls	a,x
	rts

;------------------------------------------------------------------------------
;FM 音源コマンドジャンプテーブル
;a=コマンド($F0-$FF)
FMSUBA:
	ldy		#FMSUB.FMSUBC
	pshs	y							;rts で戻る場所をスタックに積んでおく

	ldy		#FMCOM
	anda	#$0F
	asla
	jmp		[a,y]

FMCOM:
	adr		OTOPST						; F0-音色セット '@'
	adr		VOLPST						; F1-VOLUME SET 'v'
	adr		FRQ_DF						; F2-DETUNE 'D'
	adr		SETQ						; F3-SET COMMAND 'q'
	adr		LFOON						; F4-LFO SET
	adr		REPSTF						; F5-REPEAT START SET '['
	adr		REPENF						; F6-REPEAT END SET ']'
	adr		MDSET						; F7-FM 音源モードセット
	adr		STEREO						; F8-STEREO MODE 'p'
	adr		FLGSET						; F9-FLAGSET '#'
	adr		W_REG						; FA-COMMAND OF 'y'
	adr		VOLUPF						; FB-VOLUME UP ')'
	adr		HLFOON						; FC-HARD LFO
	adr		TIE							; (CANT USE)
	adr		RSKIP						; FE-REPEAT JUMP '/'
	adr		SECPRC						; FF-拡張コマンド
FMCOM2:
	adr		PVMCHG						; FF00-PCM 音量モード 'vm'
	adr		NTMEAN						; なし
	adr		HRDENV						; FFF1-ハードエンベロープ SHAPE 'S'
	adr		ENVPOD						; FFF2-ハードエンベロープ PERIOD
	adr		REVERB						; FF03-リバーブ 'R'
	adr		REVMOD						; FF04-リバーブモード 'Rm'
	adr		REVSW						; FF05-リバーブスイッチ 'RF'

;------------------------------------------------------------------------------
;[$FF] 拡張コマンドパース
SECPRC:
	lda		,x+
	anda	#$0F
	asla
	ldy		#FMCOM2
	jmp		[a,y]

;------------------------------------------------------------------------------
;ダミーコマンド
NTMEAN:
	rts

;------------------------------------------------------------------------------
;[$FD] タイコマンド
TIE:
	lda		$1F,u
	anda	#%10111111					;キーオフフラグ
	sta		$1F,u
	rts

;------------------------------------------------------------------------------
;[$F9] フラグセットコマンド
FLGSET:
	lda		,x+
	sta		FLGADR						;$F320+$1F 何に使っているかよくわからない。
	rts

;------------------------------------------------------------------------------
;[$FF03] リバーブコマンド
REVERB:
	lda		,x+
	sta		$11,u						;リバーブ加減算値
.RV1:
	lda		$21,u
	ora		#%00100000					;リバーブフラグ
	sta		$21,u
	rts

;------------------------------------------------------------------------------
;[$FF05] リバーブスイッチコマンド
REVSW:
	lda		,x+
	bne		REVERB.RV1
	lda		$21,u
	anda	#%11011111					;リバーブフラグ
	sta		$21,u
	lbsr	STVOL						;音量セット
	rts

;------------------------------------------------------------------------------
;[$FF04] リバーブモードコマンド
REVMOD:
	lda		,x+
	beq		.RM2
	lda		$21,u
	ora		#%00010000					;リバーブモード
	sta		$21,u
	rts
.RM2:
	lda		$21,u
	anda	#%11101111					;リバーブモード
	sta		$21,u
	rts

;------------------------------------------------------------------------------
;[$FF00] PCM 音量モードコマンド
PVMCHG:
	lda		,x+
	sta		PVMODE
	rts

;------------------------------------------------------------------------------
;[$F8] ステレオモードコマンド
STEREO:
	tst		DRMF1
	bne		.STE2						;リズム音源は STE2 へ
	tst		PCMFLG
	beq		.STER2						;FM 音源は STER2 へ

	lda		,x+
	sta		PCMLR
	rts

.STER2:
	lda		,x+							;パラメータを読む
	rora
	rora
	rora
	anda	#%11000000					;LR=bit76 にする
	pshs	a

	lda		FMPORT
	adda	$08,u						;チャンネル番号
	ldy		#PALDAT						;各チャンネルの PMS/AMS/LR の情報が保存されている
	ldb		a,y
	andb	#%00111111					;LFO 関係と
	orb		,s							;新しい LR を合成する
	stb		a,y							;更新
	puls	a

	lda		#$B4
	adda	$08,u						;レジスタ $B4-$B6
	lbsr	PSGOUT
	rts

.STE2:
	lda		,x							;bit0-3:リズム音の種類(0-5) bit4-5:LR
	anda	#%00001111

	ldy		#DRMVOL
	ldb		a,y
	andb	#%00011111					;音量情報をマスク
	stb		a,y

	ldb		,x+
	aslb
	aslb
	andb	#%11000000
	orb		a,y							;LR 情報と合成
	stb		a,y							;更新

	adda	#$18						;レジスタ $18
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;[$FB] 相対音量上下コマンド
VOLUPF:
	lda		,x+
	adda	$06,u
	sta		$06,u						;音量更新

	tst		PCMFLG
	bne		.exit						;PCM 音源はそのまま
	tst		DRMF1
	lbne	DVOLSET						;リズム音源と
	lbsr	STVOL						;FM 音源は音量設定へ
.exit
	rts

;------------------------------------------------------------------------------
;[$F7] FM 音源モードセットコマンド
MDSET:
	lbsr	TO_EFC						;効果音モードに切り替え

	ldy		#DETDAT
	ldd		,x++						;続くパラメータ 4byte をコピー
	std		,y++						;単純コピーなのでエンディアンは気にしなくていい
	ldd		,x++
	std		,y++
	rts

;------------------------------------------------------------------------------
;[$FC] ハードウェア LFO コマンド
HLFOON:
	ldb		,x+							;bit0-3: LFO 周波数
	orb		#%00001000					;LFO on
	lda		#$22						;レジスタ $22
	lbsr	PSGOUT

	lda		,x+							;PMS 0-7
	ldb		,x+							;AMS 0-3

	aslb
	aslb
	aslb
	aslb
	orb		-2,x						;PMS bit0-2, AMS bit4-5
	pshs	b

	lda		FMPORT
	adda	$08,u						;チャンネル番号
	ldy		#PALDAT
	ldb		a,y
	andb	#%11000000					;LR 情報をマスク
	orb		,s							;LFO と合成する
	stb		a,y							;更新

	puls	a

	lda		#$B4						;レジスタ $B4-$B6
	adda	$08,u						;チャンネル番号
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;[$F4] ソフトウェア LFO セットコマンド
LFOON:
	lda		,x+							;1byte 読み込み
	bne		LFOON3

	bsr		SETDEL						;[$F4][00][delay]
	bsr		SETCO						;[counter]
	bsr		SETVCT						;[vct.l][vct.h]
	bsr		SETPEK						;[peak]

	lda		$1F,u
	ora		#%10000000					;LFO フラグ
	sta		$1F,u
	rts

;------------------------------------------------------------------------------
;[$F4][$01-$06] ソフトウェア LFO サブコマンド
LFOON3:
	deca
	asla
	ldy		#LFOTBL
	jmp		[a,y]

LFOTBL:
	adr		LFOOFF						;[$F4][$01] ソフトウェア LFO off 'MF0'
	adr		LFOON2						;[$F4][$02] ソフトウェア LFO on 'MF1'
	adr		SETDEL						;[$F4][$03] ソフトウェア LFO delay 'MW'
	adr		SETCO						;[$F4][$04] ソフトウェア LFO counter 'MC'
	adr		SETVC2						;[$F4][$05] ソフトウェア LFO velocity 'ML'
	adr		SETPEK						;[$F4][$06] ソフトウェア LFO peak 'MD'
;	adr		SETMT						;[$F4][$07] ソフトウェア LFO を TL に適用 'MT'

;------------------------------------------------------------------------------
;[$F4][$03] ソフトウェア LFO delay コマンド
SETDEL:
	lda		,x+
	sta		$13,u						;LFO delay source
	sta		$14,u						;LFO delay work
	rts

;------------------------------------------------------------------------------
;[$F4][$04] ソフトウェア LFO counter コマンド
SETCO:
	lda		,x+
	sta		$15,u						;LFO counter source
	sta		$16,u						;LFO counter work
	rts

;------------------------------------------------------------------------------
SETVCT:
	ldb		,x+
	lda		,x+							;リトルエンディアン準拠
	std		$17,u						;LFO velocity source
	std		$19,u						;LFO velocity work
	rts

;------------------------------------------------------------------------------
;[$F4][$05] ソフトウェア LFO velocity コマンド
SETVC2:
	bsr		SETVCT
	jmp		LFORST						;LFO ディレイ再設定

;------------------------------------------------------------------------------
;[$F4][$06] ソフトウェア LFO peak コマンド
SETPEK:
	lda		,x+
	sta		$1B,u						;LFO peak source
	lsra
	sta		$1C,u						;LFO peak work
	rts

;------------------------------------------------------------------------------
;[$F4][$02] ソフトウェア LFO on コマンド
LFOON2:
	lda		$1F,u
	ora		#%10000000					;LFO フラグ
	sta		$1F,u
	rts

;------------------------------------------------------------------------------
;[$F4][$01] ソフトウェア LFO off コマンド
LFOOFF:
	lda		$1F,u
	anda	#%01111111					;LFO フラグ
	sta		$1F,u
	rts

;------------------------------------------------------------------------------
;[$F3] Q コマンド
SETQ:
	lda		,x+
	sta		$12,u						;q 値
	rts

;------------------------------------------------------------------------------
;[$F0] 音色セットコマンド
OTOPST:
	tst		PCMFLG
	bne		OTOPCM						;PCM 音源は OTOPCM へ
	tst		DRMF1
	bne		OTODRM						;リズム音源は OTODRM へ

	lda		,x+							;1byte 読み出し
	sta		$01,u	 					;音色番号
	lbsr	STENV						;FM 音色設定
	lbsr	STVOL						;TL 設定
	rts

;------------------------------------------------------------------------------
;リズム音源 音色設定
OTODRM:
	lda		,x+
	sta		RHYTHM
	rts

;------------------------------------------------------------------------------
;ADPCM 音源 音色設定
OTOPCM:
	lda		,x+
	sta		PCMNUM						;PCM 音色番号
	deca
	sta		$01,u						;音色番号(0-)
	asla
	asla
	asla

	ldy		#PCMADR						;8byte/音色のテーブル
	leay	a,y

	ldb		,y
	lda		1,y							;リトルエンディアン準拠
	std		STTADR						;スタートアドレス

	ldb		2,y
	lda		3,y							;リトルエンディアン準拠
	std		ENDADR						;エンドアドレス

	lda		5,y
	tst		PVMODE						;PCM 音量モード
	beq		.exit
	sta		$06,u						;音量
.exit:
	rts

;------------------------------------------------------------------------------
;[$F1] 音量コマンド
VOLPST:
	tst		PCMFLG
	bne		PCMVOL						;PCM 音源は PCMVOL へ
	tst		DRMF1
	bne		VOLDRM						;リズム音源は VOLDRM へ

	lda		,x+
	sta		$06,u						;音量
	lbsr	STVOL						;TL に反映
	rts

;------------------------------------------------------------------------------
;リズム音源音量設定
VOLDRM:
	lda		,x+
	sta		$06,u						;音量 リズム音源トータルレベル(0-63)
	bsr		DVOLSET						;音量を反映

;VOLDR1:
	ldy		#DRMVOL						;リズム 6 種の個別の音量と LR のバッファ
	lda		#$18
.VOLDR2:
	ldb		,y
	andb	#%11000000					;LR をマスク
	orb		,x+							;音量と合成して更新
	stb		,y+

	lbsr	PSGOUT
	inca
	cmpa	#$1E						;レジスタ $18-$1D
	bne		.VOLDR2
	rts

;------------------------------------------------------------------------------
;PCM 音量設定
PCMVOL:
	ldb		,x+
	tst		PVMODE						;PCM 音量モード
	bne		.PCMV2
	stb		$06,u						;音量
	rts
.PCMV2:
	stb		$07,u						;補正値
	rts

;------------------------------------------------------------------------------
;リズム音量設定
DVOLSET:
	ldb		$06,u
	andb	#%00111111					;リズム音源トータルレベル(0-63)
	pshs	b

	ldb		TOTALV						;マスターボリューム
	aslb
	aslb
	addb	,s
	cmpb	#$40						;64 を超えたら 0 にする
	bcs		.DV2
	clrb
.DV2:
	puls	a
	lda		#$11						;レジスタ $11
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;[$F2] デチューンコマンド
FRQ_DF:
	clr		$20,u
	ldb		,x+							;リトルエンディアン準拠
	lda		,x+

	tst		,x+
	beq		.FD2						;0 のとき絶対値
	addd	$09,u						;デチューン値
.FD2:
	std		$09,u						;更新

	tst		PCMFLG
	beq		.exit						;FM 音源はここで終了

	addd	DELT_N						;Delta-N と加算
	pshs	d
;	ldb		1,s							;下位
	lda		#$09						;レジスタ $09
	lbsr	PCMOUT

	inca								;レジスタ $10
	ldb		,s							;上位
	lbsr	PCMOUT
	puls	d
.exit:
	rts

;------------------------------------------------------------------------------
;[$FE] リピートジャンプコマンド
RSKIP:
	ldb		,x+							;リトルエンディアン準拠
	lda		,x+
	leay	d,x
	lda		-2,y						;[$FE][l][h] と [l] の位置 と hl を足す
	deca								;そこにループカウンタ loop_cnt が書いてある
	beq		.RSKIP2
	rts									;1 でなければ [h] の次から続行

.RSKIP2:								;1 の場合、
	leax	2,y							;[$F6][loop_cnt][loop_src][l][h][*]
	rts									;[*] の位置を次のアドレスとする

;------------------------------------------------------------------------------
;[$F5] リピートスタートセットコマンド
REPSTF:
	ldb		,x+							;リトルエンディアン準拠
	lda		,x+

	leay	d,x							;[$F5][l][h] と [l] の位置 と hl を足すと $F6 コマンドのパラメータ列
	lda		-2,y						;[$F6][loop_cnt][loop_src][l][h]
	sta		-3,y						;loop_src を loop_cnt に上書きする
	rts

;------------------------------------------------------------------------------
;[$F6] リピートエンドセットコマンド
REPENF:
	dec		,x							;[$F6][loop_cnt][loop_src][l][h]
	beq		.REPENF2					;カウンタをデクリメントして 0 なら REPENF2 へ

	ldb		2,x							;リトルエンディアン準拠
	lda		3,x
	leax	2,x							;[l] の位置 - hl を新しいシーケンスポインタとする

	coma								;neg d
	comb								;neg d
	addd	#$0001						;neg d
	leax	d,x
	rts

.REPENF2:
	lda		1,x							;loop_src を loop_cnt に上書きする
	sta		,x
	leax	4,x							;[h] の次から続行
	rts

;------------------------------------------------------------------------------
;FM 音源音色セット([$F0])
STENV:
	lbsr	KEYOFF
	lda		#$80						;SL/RR
	adda	$08,u						;チャンネル番号
	ldb		#$0F
.ENVLP:
	lbsr	PSGOUT						;RR=15 を書き込む
	adda	#$04
	cmpa	#$90
	bcs		.ENVLP

	lda		$01,u						;音色番号
;STENV0:
	ldb		#$19
	mul									;25byte/音色 4op*6(DT/ML,TL,KS/AR,DR,SR,SL/RR)+FB/AL
	tfr		d,y
	ldd		OTODAT
	exg		a,b							;リトルエンディアン準拠
	addd	#$0001						;[0]は総音色数
	leay	d,y
	leay	MUSICNUM,y					;曲バイナリの先頭アドレス ;;;MUSICNUM+1 でまとめてもいいか.

;STENV1:
	lda		#$30						;DT/ML から書き込み開始
	adda	$08,u						;チャンネル番号
.STENV2:
;STENV3:
	ldb		,y+
	lbsr	PSGOUT
	adda	#$04
	cmpa	#$90
	bcs		.STENV2

	ldb		,y
	andb	#$07
	stb		$07,u						;アルゴリズム
	ldb		,y
	lda		#$B0						;FB/AL
	adda	$08,u						;チャンネル番号
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;FM 音源の音量設定
;
STVOL:
	pshs	a,b,y						;一応保護しておく
	bsr		.STV1
	puls	a,b,y
	rts

.STV1:
	ldb		$06,u						;音量
	addb	TOTALV						;マスターボリューム
	cmpb	#$14
	bcs		.STV12
	clrb								;20 以上は 0 にする
.STV12:
.STV2:									;FS2 からここを呼び出し。b=引数
	ldy		#FMVDAT						;FM 音量<->TL 変換テーブル
	ldb		b,y

	ldy		#CRYDAT						;アルゴリズム別キャリア or モジュレータのテーブル。op4231=bit3210 で 1 の箇所がキャリア。
	lda		$07,u						;アルゴリズム番号
	lda		a,y
	pshs	a

	lda		#$40						;TL
	adda	$08,u						;チャンネル番号 0-2
.STVOL2:
	ror		,s
	bcc		.skip
	lbsr	PSGOUT						;元の音色の各キャリア op の TL と足さずに一律の値で TL を出力している。
.skip:
	adda	#$04
	cmpa	#$50
	bcs		.STVOL2

	puls	a
	rts

;------------------------------------------------------------------------------
;Timer-B 設定
STTMB:									;b=引数で呼び出し
;STTMB2:
	lbsr	FM7_CalcTimerB				;[FM7] Timer-B 変換処理

	lda		#$26						;b=Timer-B 設定値を書き込み
	lbsr	PSGOUT

	inca								;opn コントロールレジスタ $27
	ldb		#$2A						;Timer-B 開始
	lbsr	PSGOUT						;#オリジナルは効果音モード設定になってたので修正.
	rts

;------------------------------------------------------------------------------
;LFO 処理
PLLFO:
	tst		$1F,u						;LFO フラグが下りていたら rts
	bpl		.exit

	ldx		$02,u
	lda		-1,x
	cmpa	#$F0
	beq		.exit						;;;ひとつ前のデータが & なら rts. $FD ではなくて???

	lda		$1F,u
	bita	#%00100000					;LFO continue flag
	bne		.CTLFO

	lbsr	LFORST						;LFO delay 再設定
	lbsr	LFORST2						;LFO peak,vel 再設定
	lda		$15,u						;LFO counter source
	sta		$16,u						;LFO counter work
	lda		$1F,u
	ora		#%00100000					;LFO continue flag
	sta		$1F,u

.CTLFO:
	tst		$14,u						;LFO delay work
	beq		.CTLFO1
	dec		$14,u						;delay--
.exit:
	rts
.CTLFO1:
	dec		$16,u						;LFO counter work
	bne		.exit

	lda		$15,u						;LFO counter source
	sta		$16,u						;LFO counter work
	tst		$1C,u						;LFO peak level work
	bne		.PLLFO1

	ldd		$19,u						;LFO 変化量
	coma
	comb
	addd	#$0001						;neg d
	std		$19,u

	lda		$1B,u						;peak level source
	sta		$1C,u						;peak level work

.PLLFO1:
	dec		$1C,u						;LFO peak level
	ldd		$19,u						;LFO 変化量
	bsr		.PLS2
	rts

;------------------------------------------------------------------------------
.PLS2:
	tst		PCMFLG						;FM 音源は PLSKI2 へ
	beq		.PLSKI2						;ADPCM 音源は以下

	addd	DELT_N
	std		DELT_N

	lda		#$09						;delta-n.l
	lbsr	PCMOUT

	inca								;delta-n.h
	ldb		DELT_N
	lbsr	PCMOUT
	rts

;------------------------------------------------------------------------------
.PLSKI2:
	addd	$1D,u						;fnum と加算・更新
	std		$1D,u

	tst		SSGF1						;FM 音源は LFOP5 へ
	beq		.LFOP5						;PSG は以下

	pshs	d

	lda		$20,u						;キーコード
	lsra
	lsra
	lsra
	lsra
	beq		.SSGLFO2					;オクターブ 0 なら飛ばす
.SNUMGETL:
	lsr		,s
	ror		1,s
	deca								;オクターブごとに CT/FT を右シフト
	bne		.SNUMGETL

.SSGLFO2:
	ldb		1,s							;下位
	lda		$08,u						;PSG 音程レジスタ
	lbsr	PSGOUT

	inca
	ldb		,s							;上位
	lbsr	PSGOUT
	puls	d
	rts

;------------------------------------------------------------------------------
;FM 音源 LFO
.LFOP5:									;d=fnum
	tfr		d,y

	lda		$21,u
	bita	#%01000000					;トレモロ処理へ
	bne		.LFOP6

	lda		$08,u						;チャンネル番号
	bita	#%00000010
	beq		.PLLFO2						;ch.3 なら以下

	lda		PL_SND.PLSET1+1
	cmpa	#$6A
	bne		.PLLFO2						;現在ノーマルモード($2A)か効果音モード($6A)かをチェック

	sty		NEWFNM						;fnum 保存
.LFOP4:
	ldy		OP_SEL						;効果音モード時の ch.3 オペレータ別書き込みレジスタテーブル
	ldx		DETDAT						;効果音モード時の各オペレータ別に fnum に加算するデチューン値
.LFOP3:
	clra
	ldb		,x+
	addd	NEWFNM						;NEWFNM + DETDAT
	exg		a,b
	pshs	a

	lda		,y+							;$A6, $AC, $AD, $AE blk/fnum.h から書き込む
	lbsr	PSGOUT
	suba	#$04						;fnum.l

	puls	b
	lbsr	PSGOUT

	cmpa	#$AA
	bne		.LFOP3
	rts

.PLLFO2:
	pshs	y

	ldb		,s							;blk/fnum.h
	lda		#$A4
	adda	$08,u						;チャンネル番号
	lbsr	PSGOUT

	ldb		1,s							;fnum,l
	suba	#$04
	lbsr	PSGOUT
	puls	y
	rts

;------------------------------------------------------------------------------
;トレモロ処理
;一応バグ取り…
.LFOP6:
	pshs	y
	lda		#$40						;TL
	adda	$08,u						;チャンネル番号

	ldy		#CRYDAT
	ldb		$07,u						;アルゴリズム番号
	ldb		b,y							;アルゴリズム別キャリアオペレータフラグ bit3210=op4231 でキャリアなら1
	pshs	b

	ror		,s
	bcc		.op3
	bsr		.LFP62
.op3:
	adda	#$04
	ror		,s
	bcc		.op2
	bsr		.LFP62
.op2:
	adda	#$04
	ror		,s
	bcc		.op4
	bsr		.LFP62
.op4:
	adda	#$04						;op.4 は全 ALG でキャリア
	bsr		.LFP62
	puls	b,y
	rts
.LFP62:
	ldb		2,s							;y=fnum の下位を使う
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;LFO リセット
LFORST:
	lda		$13,u						;LFO delay source
	sta		$14,u						;LFO delay work
	lda		$1F,u
	anda	#%11011111					;LFO continue flag
	sta		$1F,u
	rts

LFORST2:
	lda		$1B,u						;LFO peak source
	lsra
	sta		$1C,u						;LFO peak work
	ldd		$17,u						;LFO velocity source
	std		$19,u						;LFO velocity work
	rts

;------------------------------------------------------------------------------
;PSG 部
SSGSUB:
	dec		,u
	beq		.SSSUB7

	lda		,u
	cmpa	$12,u						;q 値
	bne		.SSSUB0

	ldx		$02,u						;シーケンスポインタ
	lda		,x							;次の 1byte を読む
	cmpa	#$FD
	beq		.SSUB0						;続くコマンドが $FD=タイなら q 効果なし
	lbsr	SSSUBA						;キーオフ時のリリース処理へ
	rts
.SSUB0:
	lda		$1F,u						;タイなら
	anda	#%10111111					;キーオフフラグをおろして、キーオフせずに次の音へつなぐ
	sta		$1F,u

.SSSUB0:
	tst		$06,u						;ソフトエンベロープフラグ
	bpl		.exit
	lbsr	SOFENV						;ソフトエンベロープ処理 a=音量で返る
	tfr		a,b

	tst		READY
	bne		.SSSUB02
	clrb
.SSSUB02:
	lda		$07,u						;各 PSG チャンネルの音量レジスタ番号(8-10)
	lbsr	PSGOUT
.exit:
	rts

.SSSUB7:
	ldx		$02,u						;シーケンスポインタ
	lda		,x							;新規コマンド 1byte を読む
	cmpa	#$FD						;$FD=タイ
	bne		.SSSUBE
;.SSUB1:
	lda		$1F,u
	anda	#%10111111					;キーオフフラグをおろす
	sta		$1F,u
	leax	1,x							;$FD の次に進める
	bra		.SSSUBB
.SSSUBE:
	lda		$1F,u
	ora		#%01000000					;キーオフフラグを立てる
	sta		$1F,u

.SSSUBB:								;ここをコマンドからの戻り先としてスタックに積む
	lda		,x							;改めて 1byte 読み込み
	bne		.SSSUB2

	lda		$1F,u						;0 なら 1loop end flag を立てる
	ora		#%00000001
	sta		$1F,u
	ldd		$04,u						;d=ループ先取得
	lbeq	SSGEND						;0ならループせず曲終了

	tfr		d,x
;SSSUB1:
	lda		,x							;ループ先に戻ってから 1byte 読み込み

.SSSUB2:
	leax	1,x							;ポインタをすすめる
	cmpa	#$F0
	lbcc	SSSUB8						;$F0-$FF はコマンド

	tfr		a,b
	anda	#%01111111
	sta		,u							;bit0-6 を音長として格納
	tstb								;bit7 は休符フラグ
	bpl		.SSSUB6
	lbsr	SSSUBA						;キーオフ時のリリース処理
	lbra	SETPT						;ポインタを更新して終了

.SSSUB6:
	lda		,x+							;bit0-3:音程 bit4-7:オクターブ

	ldb		$1F,u
	bitb	#%01000000					;キーオフフラグ
	bne		.SSSKIP0

	cmpa	$20,u						;ひとつ前のキーコードと同じなら新規にキーオンはしない
	lbeq	SETPT						;c&c のような状態

.SSSKIP0:
	sta		$20,u						;ひとつ前のキーコードを更新
	pshs	a

	anda	#%00001111					;音階
	asla
	ldy		#SNUMB						;音階から CT/FT への変換テーブル
	ldd		a,y
	addd	$09,u						;detune
	std		$1D,u						;LFO 用ワークに保存

	lsr		,s
	lsr		,s
	lsr		,s
	lsr		,s							;オクターブ
	beq		.SSSUB4
.SSSUB5:
	lsra
	rorb								;d >>= 1
	dec		,s							;オクターブごとに右シフト
	bne		.SSSUB5

.SSSUB4:
	pshs	a
	lda		$08,u						;各 PSG チャンネルごとの CT/FT レジスタ番号(0,2,4)
	lbsr	PSGOUT
	puls	b
	inca
	lbsr	PSGOUT
	puls	a							;オクターブだったもの

	lda		$1F,u
	bita	#%01000000					;キーオフフラグ
	bne		.SSSUBF
	lbsr	SOFENV						;PSG ソフトエンベロープ処理 a=音量で返る
	bra		.SSSUB9

.SSSUBF:
	tst		$21,u						;HW エンベロープフラグ
	bpl		.SSSUBG

	ldb		#$10
	lda		$07,u						;各 PSG チャンネルの音量レジスタ番号(8-10)
	lbsr	PSGOUT

	ldb		$21,u
	andb	#%00001111
	lda		#$0D						;PSG レジスタ 13 Envelope Shape
	lbsr	PSGOUT
	bra		.SSSUBH						;SETPT に飛んだ方が良い…

.SSSUBG:
	lda		$06,u
	anda	#%00001111					;音量
	ora		#%10010000					;bit7=1:soft envelope flag bit4=1:attack flag
	sta		$06,u

	lda		$0C,u						;attack rate
	sta		$0B,u						;累積値を初期化
	lda		$1F,u
	anda	#%11011111					;LFO continue flag
	sta		$1F,u
	lbsr	SOFENV.SOFEV7				;a=音量で戻ってくる
.SSSUBH:
	ldb		$1B,u						;peak level source
	lsrb
	stb		$1C,u						;peak level work
	ldb		$13,u						;delay source
	stb		$14,u						;delay work

.SSSUB9:
.SSSUB3:								;a=音量
	tst		$21,u						;HW エンベロープフラグ
	bmi		SETPT

	tfr		a,b
	tst		READY
	bne		.SSSUB32
	clrb
.SSSUB32:
	lda		$07,u						;各 PSG チャンネルの音量レジスタ番号(8-10)
	lbsr	PSGOUT

;------------------------------------------------------------------------------
SETPT:
	stx		$02,u						;ポインタ更新して終了
	rts

;------------------------------------------------------------------------------
;[PSG] 12音階から CT/FT への変換テーブル
SNUMB:		;Hz = 1228800 / 16 / (1...4095)
	adr		$092C, $08A9, $082C, $07B7, $0748, $06DF
	adr		$067D, $061F, $05C7, $0574, $0526, $04DC

;------------------------------------------------------------------------------
;キーオフ時のリリース処理
SSSUBA:
	tst		$21,u						;HW エンベロープフラグ
	bpl		.SSUBAB
	clrb
	lda		$07,u						;各 PSG チャンネルの音量レジスタ番号(8-10)
	lbsr	PSGOUT

.SSUBAB:
	lda		$21,u
	bita	#%00100000					;リバーブフラグ
	beq		.SSUBAC
	lda		$1F,u
	anda	#%10111111					;キーオフフラグ
	sta		$1F,u
	jmp		SSGSUB.SSSUB0

.SSUBAC:
	clra
	tst		$06,u						;ソフトエンベロープフラグが下りていたら
	bpl		SSGSUB.SSSUB3				;a=音量として戻る
	lda		$06,u
	anda	#%10001111
	sta		$06,u
	lbsr	SOFENV.SOFEV9				;リリースから実行
	bra		SSGSUB.SSSUB3

;------------------------------------------------------------------------------
;PSG コマンドジャンプテーブル
;a=コマンド番号($F0-$FF)
SSSUB8:
	ldy		#SSGSUB.SSSUBB
	pshs	y							;rts で戻る場所をスタックに積んでおく

	ldy		#PSGCOM
	anda	#$0F
	asla
	jmp		[a,y]

PSGCOM:
	adr		OTOSSG						; F0-音色 '@'
	adr		PSGVOL						; F1-VOLUME SET 'v'
	adr		FRQ_DF						; F2-DETUNE 'D'
	adr		SETQ						; F3-COMMAND OF 'q'
	adr		LFOON						; F4-LFO SET
	adr		REPSTF						; F5-REPEAT START SET '['
	adr		REPENF						; F6-REPEAT END SET ']'
	adr		NOISE						; F7-MIX PORT 'P'
	adr		NOISEW						; F8-NOISE PARAMETER 'w'
	adr		FLGSET						; F9-FLAGSET '#'
	adr		ENVPST						; FA-SOFT ENVELOPE 'E'
	adr		VOLUPS						; FB-VOLUME UP ')'
	adr		NTMEAN						; FC-なし
	adr		TIE							; FD-TIE
	adr		RSKIP						; FE-リピートスキップ
	adr		SECPRC						; FF-拡張コマンド

;------------------------------------------------------------------------------
;[$FFF1] PSG ハードエンベロープコマンド(S)
HRDENV:
	ldb		,x+
	lda		#$0D						;Envelope Shape
	lbsr	PSGOUT

	orb		#%10000000					;bit7=HW エンベロープフラグ
	stb		$21,u						;bit0-3 shape
	lda		#$10
	sta		$06,u						;音量=16 にする
	rts

;------------------------------------------------------------------------------
;[$FFF2] PSG ハードエンベロープコマンド(M)
ENVPOD:
	ldb		,x+
	lda		#$0B						;Envelope Period.l
	lbsr	PSGOUT
	ldb		,x+
	inca								;Envelope Period.h
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;[$FA] 音源レジスタ直接書き込みコマンド
W_REG:
	ldd		,x++						;[$FA][reg][data]

	cmpa	#$26
	lbeq	STTMB						;FM-7 特別処理

	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;[$F7] PSG ミキサコマンド
NOISE:
	lda		$08,u						;各 PSG チャンネルの CT/FT レジスタ番号(0,2,4)
	lsra								;-> 0,1,2
	ldy		#.table						;マスクテーブル
	ldb		a,y
	andb	PREGBF+5					;先にマスクを適用して
	stb		PREGBF+5					;現在のミキサ値を更新

	ldb		,x+							;%001001 のようなフォーマット
	tsta
	beq		.noise3
.noise2:
	aslb								;b<<=1
	deca
	beq		.noise3
	aslb								;b<<=2
.noise3:
	orb		PREGBF+5					;マスク済みの値と合成して更新
	stb		PREGBF+5

	lda		#$07						;PSG レジスタ $07 ミキサレジスタ
	lbsr	PSGOUT
	rts
.table:
	byt		%11110110, %11101101, %11011011

;------------------------------------------------------------------------------
;[$F8] PSG ノイズ周波数コマンド
NOISEW:
	ldb		,x+
	lda		#$06						;PSG レジスタ $08 ノイズ周波数
	lbsr	PSGOUT
	stb		PREGBF+4					;PSG レジスタバッファ
	rts

;------------------------------------------------------------------------------
;[$FA] PSG ソフトエンベロープコマンド
ENVPST:
	ldd		,x++						;そのまま 6byte 順次格納するだけなのでエンディアンは無視
	std		$0C,u
	ldd		,x++
	std		$0E,u
	ldd		,x++
	std		$10,u

	lda		$06,u
	ora		#%10010000					;ソフトエンベロープ bit4=attack flag
	sta		$06,u
	rts

;------------------------------------------------------------------------------
;[$F0] PSG 音色セットコマンド
OTOSSG:
	lda		,x+
	anda	#%00001111					;音色番号0-15
	ldb		#$06
	mul
	pshs	x
	ldx		#SSGDAT
	leax	d,x							;x=SSGDAT+音色番号*6
	bsr		ENVPST
	puls	x
	rts

;OTOCAL:

;AL,AR,DR,SL,SR,RR
;[0]=[ix+12] 初期レベル: 累積カウンタをこの値で初期化する
;[1]=[ix+13] アタック値: アタック状態でおいて累積カウンタが $FF に達するまで足しこんでいく値
;[2]=[ix+14] ディケイ値: ディケイ状態において累積カウンタがサスティンレベルになるまで引いていく値
;[3]=[ix+15] サスティンレベル: 累積カウンタがこの値になったらサスティン状態になる.
;[4]=[ix+16] サスティン値: サスティン状態において累積カウンタが 0 になるまで引いていく値. 大きいほどリリースへの移行が速い
;[5]=[ix+17] リリース値: リリース時間. 大きいほど減衰が速い
;                       リバーブが on のとき、キーオフ後の音量に加算される(SOFEV7)
;[ix+11]: 累積カウンタ. 0-255 が 0.0-1.0 に相当し、本来の音量(0-15)の係数になる.
;
;  0 ／＼
;　／　　￣―＿4
;／ 1  2　 3　 ＼ 5
;
SSGDAT:
	byt	255, 255, 255, 255,   0, 255
	byt	255, 255, 255, 200,   0,  10
	byt	255, 255, 255, 200,   1,  10
	byt	255, 255, 255, 190,   0,  10
	byt	255, 255, 255, 190,   1,  10
	byt	255, 255, 255, 170,   0,  10
	byt	 40,  70,  14, 190,   0,  15
	byt	120, 030, 255, 255,   0,  10
	byt	255, 255, 255, 225,   8,  15
	byt	255, 255, 255,   1, 255, 255
	byt	255, 255, 255, 200,   8, 255
	byt	255, 255, 255, 220,  20,   8
	byt	255, 255, 255, 255,   0,  10
	byt	255, 255, 255, 255,   0,  10
	byt	120,  80, 255, 255,   0, 255
	byt	255, 255, 255, 220,   0, 255

;------------------------------------------------------------------------------
;[$FB] PSG 相対音量コマンド

VOLUPS:
	lda		,x+

	tst		$21,u
	bmi		.exit						;HW エンベロープフラグが立っていたら無効

	adda	$06,u
	anda	#%00001111					;現在の音量と足す
	cmpa	#$10
	bcc		.exit						;16以上になったら無効

	ldb		$06,u
	andb	#%11110000					;bit4-7 エンベロープ情報と合成して書き戻す
	stb		$06,u
	ora		$06,u
	sta		$06,u
.exit:
	rts

;------------------------------------------------------------------------------
;[$F1] PSG 音量コマンド
PSGVOL:
	lda		$21,u
	anda	#%01111111					;HW エンベロープフラグをおろす
	sta		$21,u

	lda		$06,u
	anda	#%11110000
	sta		$06,u						;bit4-7 エンベロープ情報はマスクして書き戻しておく

	lda		,x+
.PV1:									;FDOSSG から呼び出しあり a=音量
	adda	TOTALV						;マスターボリューム
	cmpa	#$10
	bcs		.PV2
	clra								;16 以上なら 0 にする
.PV2:
	ora		$06,u
	sta		$06,u						;書き戻す
	rts

;------------------------------------------------------------------------------
;全 PSG チャンネル消音
SSGOFF:
	ldd		#$0800
	lbsr	PSGOUT
	inca
	lbsr	PSGOUT
	inca
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;PSG キーオフ
SKYOFF:
	clrb
	stb		$06,u						;音量=0
	lda		$07,u						;各 PSG チャンネルの音量レジスタ番号(8-10)
	lbsr	PSGOUT
	rts

;------------------------------------------------------------------------------
;PSG ソフトエンベロープ処理
;a=音量で返す
SOFENV:
	lda		$06,u
	bita	#%00010000					;エンベロープフラグ
	beq		.SOFEV2						;Attack フラグが下りていたら Decay phase へ

	lda		$0B,u
	adda	$0D,u						;累積カウンタにアタック値を足していく
	bcc		.SOFEV1
	lda		#$FF						;$FF を上限とする
.SOFEV1:
	sta		$0B,u						;累積カウンタ更新
	cmpa	#$FF
	bne		.SOFEV7						;$FF に達したら

	lda		$06,u
	eora	#%00110000					;Attack を降ろして Decay を立てる
	sta		$06,u
	bra		.SOFEV7

.SOFEV2:
	lda		$06,u
	bita	#%00100000					;エンベロープフラグ
	beq		.SOFEV4						;Decay フラグが下りていたら Sustain phase へ

	lda		$0B,u						;Decay phase
	suba	$0E,u						;累積カウンタからディケイ値を引いていく
	bcs		.SOFEV8						;0 を下回ったり
	cmpa	$0F,u
	bcc		.SOFEV3						;サスティンレベルを下回ったりした場合は
.SOFEV8:
	lda		$0F,u						;サスティンレベルを下限とする
.SOFEV3:
	sta		$0B,u						;累積カウンタ更新
	cmpa	$0F,u
	bne		.SOFEV7						;サスティンレベルに達したらサスティン状態に移行
	lda		$06,u
	eora	#%01100000					;decay を降ろして sustain を立てる
	sta		$06,u
	bra		.SOFEV7

.SOFEV4:
	lda		$06,u
	bita	#%01000000					;エンベロープフラグ
	beq		.SOFEV9						;Sustain フラグが下りていたら Release phase へ

	lda		$0B,u						;Sustain phase
	suba	$10,u						;累積カウンタからサスティン値を引いていく
	bcc		.SOFEV5
	clra								;0 を下限とする
.SOFEV5:
	sta		$0B,u						;累積カウンタ更新
	tsta								;;;不要かも…
	bne		.SOFEV7
	lda		$06,u						;累積 0 になったら
	anda	#%10001111					;sustain を降ろして release phase へ
	sta		$06,u
	bra		.SOFEV7

.SOFEV9:								;Release phase
	lda		$0B,u
	suba	$11,u						;累積カウンタからリリース値を引いていく
	bcc		.SOFEVA
	clra								;0 を下限とするa
.SOFEVA:
	sta		$0B,u						;累積カウンタ更新

.SOFEV7:								;最終的な音量を計算して a で返す
	lda		$06,u
	anda	#%00001111					;音量
	inca
	ldb		$0B,u						;累積カウンタ(0.0-1.0 相当)の値と乗算
	mul									;d = 累積カウンタ(0-255) * 音量値(1-16) 結果の上位(a)のみ使う
	ldb		$1F,u
	bitb	#%01000000					;キーオフフラグが立っていたらそのまま
	bne		.exit
	ldb		$21,u
	bitb	#%00100000					;リバーブフラグが立っていたら
	beq		.exit
	adda	$11,u						;リリース値を足して半分にする
	lsra
.exit:
	rts									;a=音量で返す


;------------------------------------------------------------------------------
;ループせずに演奏終了
FMEND:
	stx		$02,u						;ポインタ更新
	tst		PCMFLG
	bne		PCMEND
	lbsr	KEYOFF						;FM 音源キーオフ
	rts

PCMEND:
	ldd		$0B00
	lbsr	PCMOUT						;PCM 音量設定
	ldd		$0100
	lbsr	PCMOUT						;PCM LR 出力なし
	ldd		$0021
	lbsr	PCMOUT						;PCM リセット
	rts

SSGEND:
	stx		$02,u						;ポインタ更新
	lbsr	SKYOFF						;PSG キーオフ
	lda		$1F,u
	anda	#%01111111					;LFO フラグを降ろす
	sta		$1F,u
	rts

;------------------------------------------------------------------------------
;ワークエリア初期化
WORKINIT:
	clr		C2NUM						;通しチャンネル番号（とくに使ってない）
	clr		CHNUM						;チャンネル番号 FM1-3=0-2 FM4-6=0-2 PSG1-3=3-5
	clr		PVMODE						;PCM volume Mode（音量補正モード）

	ldx		#MU_TOP						;曲データバイナリ先頭+5
	lda		MUSICNUM					;曲データにに含まれる総曲数-1（リクエスト曲番号で上書きされる）
.WI1:
	beq		.WI2
	pshs	a							;曲テンポ情報 + 4byte * 総チャンネル分のヘッダ部を飛ばす
	ldd		1 + MAXCH * 4,x				;d = 曲データ部の終端 + 1 （バイナリ先頭からの相対値）
	exg		a,b							;リトルエンディアンにする
	leax	d,x
	puls	a
	deca
	bra		.WI1
.WI2:
	lda		,x+
	sta		TIMER_B						;曲テンポ
	stx		TB_TOP						;FM1 データオフセット

	ldu		#CH1DAT
.WI4:
	bsr		FMINIT						;FM1-3, PSG1-3 を初期化
	ldd		#WKLENG
	leau	d,u
	cmpu	#CH1DAT + WKLENG * 6
	bne		.WI4

	clr		CHNUM
	ldu		#DRAMDAT
	bsr		FMINIT						;リズム音源を初期化

	clr		CHNUM
	ldu		#CHADAT
.WI6:
	bsr		FMINIT						;FM4-6, ADPCM を初期化
	ldd		#WKLENG
	leau	d,u
	cmpu	#CHADAT + WKLENG * 4
	bne		.WI6
	rts

;1ch 分のワークエリア初期化処理
FMINIT:
	clrb
.loop:
	clr		b,u
	incb
	cmpb	#WKLENG
	bne		.loop

	lda		#$01
	sta		,u							;初期音長=1
	clr		$06,u						;初期音量=0

	ldx		TB_TOP						;FM1 データオフセット
	ldd		,x++
	exg		a,b							;リトルエンディアンにする
	addd	#MU_TOP						;曲データ部先頭（;;;複数曲が含まれる場合これで良いのか？）
	std		$02,u						;曲データポインタアドレスを格納

	ldd		,x++
	beq		.FMI2
	exg		a,b							;リトルエンディアンにする
	addd	#MU_TOP
	std		$04,u						;曲ループ時に戻るアドレスを格納
.FMI2:
	inc		C2NUM						;通しチャンネル番号（特に使っていない）
	stx		TB_TOP						;ヘッダのポインタ+=4

	lda		CHNUM
	cmpa	#$03
	bcc		.SSINIT						;PSG は専用初期化へ

	sta		$08,u						;チャンネル番号
	inca
	sta		CHNUM						;チャンネル番号 FM1-3=0-2 FM4-6=0-2 PSG1-3=3-5
	rts

.SSINIT:
	adda	#$05
	sta		$07,u						;音量レジスタ番号 8,9,10
	lda		CHNUM
	suba	#$03
	asla
	sta		$08,u						;CT/FT レジスタ番号 0,2,4

	inc		CHNUM
	rts

;------------------------------------------------------------------------------
;FM ch.3 ノーマル／効果音モード切替
TO_NML:
	ldb		#$2A						;ノーマルモード, Timer-B On
	stb		PL_SND.PLSET1+1
.TNML2:
	lda		#$27
	lbsr	PSGOUT
	rts

TO_EFC:
	ldb		#$6A						;効果音モード, Timer-B On
	stb		PL_SND.PLSET1+1
	bra		TO_NML.TNML2

;------------------------------------------------------------------------------
;ADPCM 再生
PLAY:
	tst		READY
	beq		.exit

	ldd		#$0B00						;volume
	bsr		PCMOUT
	ldd		#$0100						;LR 出力なし
	bsr		PCMOUT

	ldd		#$0021						;reset
	bsr		PCMOUT
	ldd		#$1008						;BRDY フラグのみマスク
	bsr		PCMOUT
	ldd		#$1080						;IRQ 全フラグリセット
	bsr		PCMOUT

	ldb		STTADR+1
	lda		#$02						;start.l
	bsr		PCMOUT
	ldb		STTADR
	inca								;start.h
	bsr		PCMOUT

	ldb		ENDADR+1
	lda		#$04						;end.l
	bsr		PCMOUT
	ldb		ENDADR
	inca								;end.h
	bsr		PCMOUT

	ldb		DELT_N+1
	lda		#$09						;delta-n.l
	bsr		PCMOUT
	ldb		DELT_N
	inca								;delta-n.h
	bsr		PCMOUT

	ldd		#$00A0						;start=1 mem_data=1
	bsr		PCMOUT

	lda		#$0B						;volume
	ldb		TOTALV
	aslb
	aslb
	addb	$06,u						;音量
	cmpb	#250
	bcs		.PL1
	clrb								;250 を超えたら 0 にする
.PL1:
	tst		PVMODE						;PCM 音量モード!=0 なら
	beq		.PL2
	addb	$07,u						;補正値を足す
.PL2:
	bsr		PCMOUT

	lda		#$01						;LR, 再生開始
	ldb		PCMLR
	rorb
	rorb
	rorb								;rrca 無いねん
	andb	#%11000000
	bsr		PCMOUT

	lda		PCMNUM
	sta		P_OUT
.exit:
	rts

;------------------------------------------------------------------------------
;ADPCM レジスタ書き込み
PCMOUT:
	rts									;[FM7] 書き込まない

	pshs	a,b,x
	ldx		#$FD45

;PCMO2:
	sta		$01,x
	lda		#$03
	sta		,x
	clr		,x

	stb		$01,x
	deca
	sta		,x
	clr		,x

	puls	a,b,x
	rts

;------------------------------------------------------------------------------
INFADR:
	ldu		#NOTSB2
	rts

;------------------------------------------------------------------------------
;音源ボードタイプチェック
;NOTSB2=0:存在する 
;[FM7] オリジナルでは OPNA のチェックだが、FM 版では FM 音源カードの存在チェックとする
CHK:
	lda		#$FE						;0 以外 = OPNA が存在しない

	ldx		#$FD15						;標準音源
	bsr		.STT1
	bne		.STTE						;==存在 !=不在
	lbsr	FM7EnvDisp

	ldx		#$FD45						;WHG 側
	bsr		.STT1
	bne		.STTE						;==存在 !=不在
	lbsr	FM7EnvDisp

	clr		NOTSB2						;どちらも存在したら OPNA 相当ということにしておく（仮）
.STTE:
	rts

.STT1:
	pshs	d,x

	ldd		#$0306
	stb		1,x
	sta		,x
	clr		,x
	ldd		#$021A
	stb		1,x
	sta		,x
	clr		,x							;レジスタ R.6 に $1A を適当に書き込んでみる(PSG なので busy は見なくてよい)

;	lda		#$FF						;レジスタアドレス $FF を指定してリードすると OPNA の場合 1 が返る. OPNA でない場合は不定($FF)

	lda		#$01						;レジスタリード
	sta		,x
	ldb		$01,x						;読みだした値
	clr		,x
	cmpb	#$1A
	puls	d,x
	rts

FM7_Busy:
	pshs	d
	clrb								;256 回は待つ
.wait:
	lda		#$04
	sta		,x
	lda		1,x
	clr		,x
	tsta
	bpl		.exit
	decb
	bne		.wait
	puls	d
	decb								;zf=0 で異常終了
	rts
.exit:
	clra
	puls	d
	rts									;zf=1 で正常終了
;------------------------------------------------------------------------------
ESC_PRC:
TIME0:									;"TIME"がアセンブラでエラーになるので "TIME0" に変更
PUTWK:
	rts

TSC:
	ldu		#CH1DAT
	ldb		#MAXCH						;11 チャンネル
.loop:
	lda		$1F,u
	bita	#%00000001
	beq		.skip
	decb
.skip:
	leau	WKLENG,u
	cmpu	#PCMDAT+WKLENG
	bne		.loop
	stb		T_FLAG						;すべてのチャンネルが 1 ループしていれば 0 になる
	rts


WKGET:									;a:ch 番号(1-11)
	deca
	pshs	b
	ldb		WKLENG
	mul
	ldu		#CH1DAT
	leau	d,u
	puls	b
	rts

;------------------------------------------------------------------------------
;[FM7] FM-7 専用処理
FM7CHK:
	ldx		#MUSICNUM
	lda		,x
	ldu		1,x
	cmpa	#"M"						;バイナリの頭に'MUB'が付いていたら 80byte を詰める（手抜き）
	bne		.skip
	cmpu	#"UB"
	bne		.skip
	leau	$50,x
	ldb		3,u
	lda		4,u							;リトルエンディアン準拠 バイナリの長さ
	addd	#$0001						;なんか長さが -1 されてる気がするので +1 しておく
	tfr		d,y
.transloop:
	lda		,u+
	sta		,x+
	leay	-1,y
	bne		.transloop

.skip:
	ldd		$FFF8
	std		FM7_IRQSTACK
	ldd		$FFF6
	std		FM7_FIRQSTACK

	lda		#$01
	sta		READY
	lbsr	CHK
	clra								;曲番号を渡す方法が現時点で無いので暫定で 0 固定にする。
	rts

FM7EnvDisp:
	pshs	d,x
	tfr		x,d
	ldx		#.TextStr+1
	bsr		Hex2Asc
	tfr		b,a
	bsr		Hex2Asc

	ldx		#.RCB						;X に Request Control Block を設定して
	jsr		[$FBFA]						;BIOS 呼び出し
	puls	d,x
	rts
.RCB:
	byt		$14, 0
	adr		.TextStr
	adr		.TextStrEnd - .TextStr
	adr		0

.TextStr:
	byt		"$FD15: OPN found.",$0D,$0A
.TextStrEnd:


Hex2Asc:
	pshs	a
	lsra
	lsra
	lsra
	lsra
	adda	#$90
	daa
	adca	#$40
	daa
	sta		,x+
	puls	a
	anda	#$0F
	adda	#$90
	daa
	adca	#$40
	daa
	sta		,x+
	rts

;BREAK キーを押したら演奏終了して BASIC に戻る
FM7KEY:
	clr		READY						;（仮）BASIC に戻る
	rti

;Timer-B 変換
;PC88 prescaler=6
;3993600 / 16 * 12 * 6 * (256 - n) = Hz
;最小は 3466.666666 毎秒
;FM7 prescaler=3
;1228800 / 16 * 12 * 3 * (256 - n) = Hz
;最小は 2133.333333 毎秒
;
;FM7 = 2133.3333 / 3466.6666 * PC88
;FM7 = 0.615384617603550338 * PC88
;FM7 = 157.538462106508887 * PC88 / 256
;FM7 = ($9D * PC88) >> 8

FM7_CalcTimerB:
	negb								;256-pc88timerb
	lda		#$9D
	mul
	exg		a,b
	negb								;256-fm7timerb
	rts

;FM-7 Specific workarea
FM7_IRQMSK:			byt		$00			;$08=演奏 $00=演奏停止 I/O $32(PC88) の代用
FM7_IRQSTACK:		adr		$0000
FM7_FIRQSTACK:		adr		$0000


;------------------------------------------------------------------------------
;音源ドライバ用ワークエリア
;
NOTSB2:		byt		0					;0=OPNA
READY:		byt		0					;Keyon Enable / Disable
TOTALV:		byt		0					;マスターボリューム
FDCO:		byt		0, 0				;フェードアウトカウンタ整数,小数

SSGF1:		byt		0					;$FF=SSG 処理中 $00=処理中でない
DRMF1:		byt		0					;$FF=リズム処理中 $00=処理中でない
FMPORT:		byt		0					;0=FM1-3 4=FM4-6
FNUM:		adr		0					;音程周波数値テンポラリ

NEWFNM:		adr		0					;blk/fnum, ct/ft
CHNUM:		byt		0					;チャンネル番号 初期化時に使用
C2NUM:		byt		0					;通しチャンネル番号 特に使っていない
TB_TOP:		adr		0					;FM1 データオフセット
TIMER_B:	byt		100					;曲テンポ


;FM 音源 12音階から blk/fnum への変換テーブル
;Prescale が FM=1/3 SSG=1/2 であることに注意.
FNUMB:		adr		$03ED, $0428, $0468, $04AB, $04F2, $053D
			adr		$058D, $05E1, $063B, $069A, $06FE, $0769

FMVDAT:		byt		$36, $33, $30, $2D	; -4  -3  -2  -1	FM音源用音量変換テーブル(v->TL)
			byt		$2A, $28, $25, $22	;  0,  1,  2,  3
			byt		$20, $1D, $1A, $18	;  4,  5,  6,  7
			byt		$15, $12, $10, $0D	;  8,  9, 10, 11
			byt		$0A, $08, $05, $02	; 12, 13, 14, 15

CRYDAT:		byt		$08	; %1000			アルゴリズム別
			byt		$08	; %1000			op.4231 の順で"1"がキャリアオペレータを表す
			byt		$08	; %1000
			byt		$08	; %1000
			byt		$0C	; %1100
			byt		$0E	; %1110
			byt		$0E	; %1110
			byt		$0F	; %1111

OP_SEL:		byt		$A6, $AC, $AD, $AE	;op. 4,3,1,2 FM3 効果音モード時の各オペレータごとの blk/fnum レジスタ番号

DETDAT:		byt		0	; op.1			FM3 効果音モードでの各オペレータごとのスロットデチューンの値
			byt		0	; op.2
			byt		0	; op.3
			byt		0	; op.4

PALDAT:		byt		$C0					;FM チャンネル別 LR/PMS/AMS バッファ
			byt		$C0
			byt		$C0
			byt		0
			byt		$C0
			byt		$C0
			byt		$C0

PREGBF:		byt		 0, 0, 0, 0, 0, 0, 0, 0, 0	;PSG レジスタバッファ
INITPM:		byt		0, 0, 0, 0, 0, 56 ,0, 0, 0	;PSG レジスタ初期化用テーブル

;------------------------------------------------------------------------------
RHYTHM:		byt		0					;現在選択中のリズム音色

DRMVOL:		byt		$C0	; bd			リズム音源各音色の音量と LR バッファ
			byt		$C0	; sd
			byt		$C0	; sym
			byt		$C0	; hh
			byt		$C0	; tom
			byt		$C0	; rim


;------------------------------------------------------------------------------
PCMNMB:		adr		$49BA + 200, $4E1C + 200, $52C1 + 200, $57AD + 200	;C-B までの再生サンプリングレート（PC88 仕様）
			adr		$5CE4 + 200, $626A + 200, $6844 + 200, $6E77 + 200
			adr		$7509 + 200, $7BFE + 120, $835E + 200, $8B2D + 200

PVMODE:		byt		0					;ADPCM volume mode
P_OUT:		byt		0					;ADPCM 音色番号
PCMLR:		byt		0					;ADPCM チャンネル LR バッファ

STTADR:		adr		0					;再生開始アドレス
ENDADR:		adr		0					;再生終了アドレス
DELT_N:		adr		0					;ADPCM 再生レート
PCMNUM:		byt		0					;音色番号
PCMFLG:		byt		0					;$FF=現在 ADPCM 処理中 $00=処理中でない

;------------------------------------------------------------------------------
;FM 音源ワークエリア(FM1-3)
;[00]    音長カウンタ
;[01]    音色番号
;[02-03] 現在のアドレス
;[04-05] 曲ループ先アドレス (0=ループしない)
;[06]    音量
;[07]    音色アルゴリズム番号
;[08]    チャンネル番号(0,1,2)
;[09-0A] デチューン
;[0B-11] 空き
;[12]    q 値
;[13]    LFO delay source
;[14]    LFO delay work
;[15]    LFO counter source
;[16]    LFO counter work
;[17-18] LFO velocity source
;[19-1A] LFO velocity work
;[1B]    LFO peak source
;[1C]    LFO peak work
;[1D-1E] blk/fnum
;[1F]    bit7=LFO FLAG
;        bit6=キーオフフラグ
;        bit5=LFO CONTINUE FLAG
;        bit3=ミュートフラグ
;        bit0=1 LOOP END FLAG
;[20]    以前のキーコード
;[21]    bit6=トレモロフラグ
;        bit5=リバーブフラグ
;        bit4=リバーブモード
;[22-25] 空き

CH1DAT:		dfs		38
CH2DAT:		dfs		38
CH3DAT:		dfs		38
;------------------------------------------------------------------------------
;PSG 音源ワークエリア
;[00]    音長カウンタ
;[01]    音色番号
;[02-03] 現在のアドレス
;[04-05] 曲ループ先アドレス (0=ループしない)
;[06]    bit7=Soft Envelope Flag (Release Flag)
;        bit6=Sustain Flag
;        bit5=Decay Flag
;        bit4=Attack Flag
;        bit3-0=音量
;[07]    PSG 音量レジスタ番号(8,9,10)
;[08]    PSG CT/FT レジスタ番号(0,2,4)
;[09-0A] デチューン
;[0B]    Soft Envelope 累積カウンタ
;[0C]    Soft Envelope 初期レベル
;[0D]    Soft Envelope Attack Rate
;[0E]    Soft Envelope Decay Rate
;[0F]    Soft Envelope Sustain Level
;[10]    Soft Envelope Sustain Rate
;[11]    Soft Envelope Release Rate
;[12]    q 値
;[13]    LFO delay source
;[14]    LFO delay work
;[15]    LFO counter source
;[16]    LFO counter work
;[17-18] LFO velocity source
;[19-1A] LFO velocity work
;[1B]    LFO peak source
;[1C]    LFO peak work
;[1D-1E] ct/ft
;[1F]    bit7=LFO FLAG
;        bit6=キーオフフラグ
;        bit5=LFO CONTINUE FLAG
;        bit3=ミュートフラグ
;        bit0=1 LOOP END FLAG
;[20]    以前のキーコード
;[21]    bit7=ハードウェアエンベロープフラグ
;        bit5=リバーブフラグ
;        bit4=リバーブモード
;[22-25] 空き

CH4DAT:		dfs		38
CH5DAT:		dfs		38
CH6DAT:		dfs		38
;------------------------------------------------------------------------------
;リズム音源ワーク
;[00]    音長カウンタ
;[01]    空き
;[02-03] 現在のアドレス
;[04-05] 曲ループ先アドレス (0=ループしない)
;[06]    トータルレベル (0-63)
;[07-11] 空き
;[12]    q 値
;[13-1E] 空き
;[1F]    bit6=キーオフフラグ
;        bit3=ミュートフラグ
;        bit0=1 LOOP END FLAG
;[20]    ひとつ前のキーコード
;[21-25] 空き

DRAMDAT:	dfs		38
;------------------------------------------------------------------------------
;FM 音源ワークエリア(FM4-6)

CHADAT:		dfs		38
CHBDAT:		dfs		38
CHCDAT:		dfs		38
;------------------------------------------------------------------------------
;ADPCM 音源ワークエリア
;[00]    音長カウンタ
;[01]    音色番号
;[02-03] 現在のアドレス
;[04-05] 曲ループ先アドレス (0=ループしない)
;[06]    音量
;[07]    音量補正値
;[08]    空き
;[09-0A] デチューン
;[0B-11] 空き
;[12]    q 値
;[13-1E] 空き
;[1F]    bit6=キーオフフラグ
;        bit3=ミュートフラグ
;        bit0=1 LOOP END FLAG
;[20]    ひとつ前のキーコード
;[21-25] 空き

PCMDAT:		dfs		38
;------------------------------------------------------------------------------
T_FLAG		byt 	0					;すべてのチャンネルが 1 ループしていれば 0 になる
FLGADR		byt		0					;曲から外部へのコントロール用
ESCAPE		byt		0					;ESC を押すと反転
