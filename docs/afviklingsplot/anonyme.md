# Anonyme faser

Det er lidt træls, hvis man skal redegøre separat for hver enkelt fase en instruktion
gennemløber i en moderne mikroarkitektur. Det skyldes at moderne mikroarkitekturer
afvikler instruktioner i mange forskellige faser.

## Længere pipelines

I moderne CMOS er det ikke realistisk at lave et cache-opslag på en enkelt cyklus.
Typisk bruges tre cykler, fuldt pipelinet. Oftest er det heller ikke muligt at
fuldt afkode en instruktion på en enkelt cyklus.

Vi kunne navngive hver enkelt af de ekstra faser der kræves og opskrive regler
for hver af dem. Vi vælger en simplere notation: Når vi opskriver faserne for
en instruktionsklasse kan vi

* tilføje anonyme faser som er påkrævet med `-` og
* angive hvor mange instruktioner der kan befinde sig i "mellemrummet" mellem
  to navngivne faser.

Man kan vælge at betragte tidligere beskrivelser af begrænsinger som specialtilfælde,
hvor *ingen* instruktioner må være i anonyme faser, dvs: `F-D: 0`, `D-X: 0`, `X-M: 0`, `M-W: 0`.
Her betyder såleds "`F-D: 0`" at der ingen instruktioner må være, som har gennemført fase
F, men ikke påbegyndt D. Med andre ord: Fase `D` skal følge direkte efter fase `F` i afviklingsplottet

For eksempel:
~~~
resC: max pr clk: F-D: 4, D-X: 2, M-W: 2
~~~
Angiver fire ekstra instruktioner mellem `F` og `D`, 2 ekstra mellem `D` og `X` og to ekstra
mellem `M` og `W`.

Så vi i alt har:
~~~
aritmetik:  F--D-XW
movq (a),b: F--D-XM--W
movq b,(a): F--D-XM

dataafhængigheder:
aritmetik a op b: X.time >= max(a.time, b.time); b.time = X.time + 1
movq (a),b: X.time >= a.time; M.time >= MEM[a].time; b.time = M.time + 3
movq b,(a): X.time >= a.time, M.time >= b.time; MEM[a].time = S.time + 3

inorder(F,D,X,M,W)
resB: max pr clk: F:2, D:2, X:2, M:1, W:2
resC: max pr clk: F-D: 4, D-X: 2, M-W: 2
~~~
Hvilket giver følgende afvikling
~~~
                 012345678901234567
movq (r10),r11   F--D-XM--W            r11.time = 9
addq $100,r11    F--D-----XW           X.time >= r11.time -> Forsinket X, r11.time = 10
movq r11,(r10)    F--D----XM           X.time >= r10.time, M.time >= r11.time
addq $8,r10       F--DDDDD-XW          r10.time = 11
movq (r10),r11     F--DDDD--XM--W      X.time >= r10.time, r11.time = 15
addq $100,r11      F------D-----XW     X.time >= r11.time -> Forsinket X, r11.time = 16
movq r11,(r10)      F-----DD----XM     X.time >= r10.time, M.time >= r11.time
addq $8,r10         F------DDDDD-XW    r10.time = 17
~~~
Vores specifikation kan kræve anonyme faser, f.eks. to mellem `F` og `D` som ovenfor,
men vi kan også indsætte yderligere anonyme faser i afviklingsplottet for at
få afviklingen til at overholde andre begrænsninger.

## Abstraktion

Anonyme faser gør det nemmere at se bort fra ting der ikke har interesse.
For eksempel kan vi udelade afkodningstrinnet fra vores beskrivelse, men få samme afvikling:
~~~
aritmetik:  F----XW
movq (a),b: F----XM--W
movq b,(a): F----XM

dataafhængigheder:
aritmetik a op b: X.time >= max(a.time, b.time); b.time = X.time + 1
movq (a),b: X.time >= a.time; M.time >= MEM[a].time; b.time = M.time + 3
movq b,(a): X.time >= a.time, M.time >= b.time; MEM[a].time = S.time + 3

inorder(F,X,M,W)
resB: max pr clk: F:2, X:2, M:1, W:2
resC: max pr clk: F-X: 8, M-W: 2
~~~
Hvilket giver den samme afvikling, blot er `D` ikke nævnt.
~~~
                 012345678901234567
movq (r10),r11   F----XM--W            r11.time = 9
addq $100,r11    F--------XW           X.time >= r11.time -> Forsinket X, r11.time = 10
movq r11,(r10)    F-------XM           X.time >= r10.time, M.time >= r11.time
addq $8,r10       F--------XW          r10.time = 11
movq (r10),r11     F--------XM--W      X.time >= r10.time, r11.time = 15
addq $100,r11      F------------XW     X.time >= r11.time -> Forsinket X, r11.time = 16
movq r11,(r10)      F-----------XM     X.time >= r10.time, M.time >= r11.time
addq $8,r10         F------------XW    r10.time = 17
~~~

Bemærk iøvrigt at selvom denne maskine kan håndtere 2 instruktioner per clk, så
opnår den i ovenstående eksempel 8/11 IPC, dvs mindre end 1 instruktion per clk.


## Køer

TBD

## Cache-miss

TBD


