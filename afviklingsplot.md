# Afviklings Plot

af Finn Schiermer Andersen, DIKU, 2019

Denne lille note introducerer afviklingsplot.

Et afviklingsplot er en idealiseret illustration af hvordan en mikroarkitektur
afvikler en strøm af instruktioner. Det er også et redskab til at bestemme en
mikroarkitekturs ydeevne for en strøm af instruktioner.

## Ide

Under afvikling af hver instruktion på en given mikroarkitektur gennegår
instruktionen forskellige faser. Et afviklingsplot angiver tidspunktet
for hver væsentlig fase en instruktion gennemløber. Instruktionsstrømmen
angives til venstre, oppefra og ned. Tiden angives i clock-perioder fra
venstre mod højre.

Her er for eksempel afviklingen af 4 instruktioner på en single cycle mikroarkitektur
~~~
                 0123
movq (r10),r11   X
addq $100,r11     X
movq r1,(r10)      X
addq $1,r10         X
~~~
Der er kun en fase. 'X' for eXecute. Det kan ikke være nemmere.

## Faser og resourcer

En instruktion gennemgår nogle faser når den afvikles. Nogle faser er generiske. 
Nogle afhænger af instruktionen.

Faserne gennemløbes i rækkefølge bestemt af instruktionstype og mikroarkitektur

Betragt for eksempel en afviklingen på en simpel pipeline, typisk for de første RISC 
maskiner konstrueret i 80'erne. Her er der fem faser: FDXMW (Fetch, Decode, eXecute, 
Memory, Writeback). 

Alle instruktioner passerer gennem de samme fem trin

Her ses nogle begrænsninger for en 5-trins pipeline
~~~
alle instruktioner:  FDXMW
ressourcer: F:1, D:1, X:1, M:1, W:1
~~~
Bemærk at det er en voldsom forenkling at udtrykke begrænsningen for
instruktionshentning i et antal instruktioner. For en maskine med instruktioner
af forskellig længde er bindingen mere korrekt udtrykt som et antal bytes.
Først i forbindelse med afkodning er det klart, hvor en instruktion begynder
og slutter. Den lille detalje vil vi se bortfra.

Her er et afviklingsplot:
~~~
                 01234567
movq (r10),r11   FDXMW
addq $100,r12     FDXMW
movq r13,(r10)     FDXMW
addq $1,r10         FDXMW
~~~

Men hov! Hvorfor kunne det ikke være:
~~~
                 01234567
movq (r10),r11   FDXMW
addq $100,r12       FDXMW
movq r13,(r10)     FDXMW
addq $8,r10       FDXMW
~~~
Vi har måske lidt svært ved at se, hvordan en maskine overhovedet skulle
kunne konstrueres således at ovenstående afviklingsrækkefølge kunne finde sted.

Vi indfører derfor en begrænsning mere: Hver fase gennemføres i instruktions-rækkefølge.
~~~
inorder(F,D,X,M,W)
~~~


## Data afhængigheder

Instruktioner bruger en eller flere clock-perioder til at producere et
resultat. Det kaldes instruktionens latenstid. Latenstiden er den tid
der går fra instruktionen modtager/fremfinder sin sidste indgående operand
og til en efterfølgende instruktion som afhænger af resultet kan begynde
sin beregning.

Man planlægger normalt en mikroarkitektur således at de grundlæggende
aritmetisk og logiske instruktioner har en latenstid på en enkelt clock
periode.

Andre instruktioner kan så få længere latenstid, fordi de udfører et mere
kompliceret stykke arbejde. For eksempel er multiplikation mere kompliceret
end addition og har derfor en latenstid på 3-4 clock perioder.

Tilgang til lageret er også mere kompliceret og tager længere tid end en
enkelt clock periode.

Ex: 5-trins pipeline, data forwarding
~~~
alle instruktioner:  FDXMW

dataafhængigheder:
simpel aritmetik a op b: X.time >= max(a.time, b.time); b.time = X.time + 1
multiplikation   a op b: X.time >= max(a.time, b.time); b.time = X.time + 4
movq (a),b: X.time >= a.time; M.time >= MEM[a].time; b.time = M.time + 1
movq b,(a): X.time >= a.time, M.time >= b.time; MEM[a].time = S.time + 1

inorder(F,D,X,M,W)
resourcer pr clk: F:1, D:1, X:1, M:1, W:1
~~~
Giver følgende afvikling:
~~~
                 012345678
movq (r10),r11   FDXMW          r11.time = 4
addq $100,r11     FDDXMW        X.time >= r11.time -> Forsinket X, STALL i D, r11.time = 5
movq r11,(r10)     FFDXMW       resA -> Forsinket D, STALL i F, X.time >= r10.time, S.time >= r11.time
addq $8,r10          FDXMW      resA -> forsinket F, r10.time = 7
~~~
Bemærk hvorledes instruktion nr 2 bliver forsinket en clock periode i sin D-fase,
fordi den afhænger af r11 som bliver produceret af den forudgående instruktion
der har en latenstid på 2 clock-perioder.


# Superskalar mikroarkitektur

I jagten efter højere ydeevne kan man finde på at skrue op for resourcerne.
Hvis der er mere end en instruktion der udfører sin X-fase samtidigt, taler
man om en superskalar maskine.

En simpel 2-vejs superskalar kan håndtere 2 instruktioner samtidigt i
faserne F,D,X og W, men kun 1 instruktion samtidigt i fase M. Det er motiveret
af at fase M er dyrere end de andre. Til gengæld vil man knytte forskellige faser
til forskellige klasser af instruktioner, således at ikke alle har en fase M.
Man kan også undgå en fase W for instruktioner der ikke skriver til et resultat
register
~~~
simpel aritmetik:  FDXW
movq (a),b: FDXMW
movq b,(a): FDXM

dataafhængigheder:
aritmetik a op b: X.time >= max(a.time, b.time); b.time = X.time + 1
movq (a),b: X.time >= a.time; M.time >= MEM[a].time; b.time = M.time + 1
movq b,(a): X.time >= a.time, M.time >= b.time; MEM[a].time = S.time + 1

inorder(F,D,X,M,W)
resourcer pr clk: F:2, D:2, X:2, M:1, W:2
~~~
Giver os følgende afvikling:
~~~
                 012345678
movq (r10),r11   FDXMW          r11.time = 4
addq $100,r11    FDDDXW         X.time >= r11.time -> Forsinket X, Gentag D, r11.time = 5
movq r11,(r10)    FDDXM         resB -> Forsinket D, Gentag F, X.time >= r10.time, M.time >= r11.time
addq $8,r10       FFFDXW        resB -> Gentag F, r10.time = 7
~~~

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

* tilføje anonyme faser som er påkrævet med "-" og
* angive hvor mange instuktioner der kan befinde sig i "mellemrummet" mellem
  to navngivne faser.

Man kan vælge at betragte tidligere beskrivelser af begrænsinger som specialtilfælde,
hvor *ingen* instruktioner må være i anonyme faser, dvs: F-D: 0, D-X: 0, X-M: 0, M-W: 0.
Her betyder såleds "F-D: 0" at der ingen instruktioner må være, som har gennemført fase
F, men ikke påbegyndt D. Med andre ord: Fase D skal følge direkte efter fase F i afviklingsplottet

For eksempel:
~~~
resC: max pr clk: F-D: 4, D-X: 2, M-W: 2
~~~
Angiver 4 ekstra instruktioner mellem F og D, 2 ekstra mellem D og X og to ekstra
mellem M og W.

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
Vores specifikation kan kræve anonyme faser, f.eks. 2 mellem F og D som ovenfor,
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
Hvilket giver den samme afvikling, blot er 'D' ikke nævnt.
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


# Out-of-order

## Faser i program-rækkefølge - eller ej

Man kunne jo forestille sig:
~~~
                 012345678
movq (r10),r11   FDXMW          r11.time = 4
addq $100,r11    FDDDXW         X.time >= r11.time -> Forsinket X, Gentag D, r11.time = 5
movq r9,(r14)     FDXM          X.time >= r14.time, M.time >= r9.time  <---- BEMÆRK!
addq $1,r10       FFDXXW        resB -> Gentag F, r10.time = 5 (eller 6)
~~~
Bemærk at instruktion nummer 3 her får sin X-fase en clock periode tidligere end instruktionen
før. På en måde overhaler instruktion nummer 3 altså instruktion nummer 2.

Men det tillader vores inorder() erklæring ikke og giver os i stedet:
~~~
                 012345678
movq (r10),r11   FDXMW          r11.time = 4
addq $100,r11    FDDDXW         X.time >= r11.time -> Forsinket X, Gentag D, r11.time = 5
movq r9,(r14)     FDDXM         inorder(X) -> Forsinket X, vent i D, X.time >= r14.time, M.time >= r9.time
addq $1,r10       FFFDXW        resB -> Gentag F, r10.time = 7
~~~

Vi kan ane at der findes mere ydeevne i form af mere parallellisme i udførelsen, hvis vi
blot kan afvige fra inorder-kravet i en eller flere faser.

Det har man gjort for "special cases" i mange maskiner gennem årene, men de sidste 20 år er der
etableret en mere generel "standard model" for out-of-order maskiner

## Standardmodellen for out-of-order mikroarkitektur

### Inorder og out-of-order

I denne model passerer instruktioner først i programrækkefølge gennem en pipeline hvor de ender i
en skeduleringsenhed (scheduler). Derfra kan de udføres uden at overholde programrækkefølgen.
Efter udførsel placeres resultaterne i en form for kø. Resultaterne udtages fra denne kø og fuldføres
i programrækkefølge. Det gælder såvel for skrivninger til registre, som for skrivninger til lageret.

Vi kan beskrive det ved følgende faser der er fælles for alle instruktioner:
* F: Start på instruktionshentning
* Q: Ankomst til scheduler
* C: Fuldførelse

Og vi benytter lejligheden til at fjerne "W" trinnet fra beskrivelsen.

### Lagerreferencer

I de hidtil beskrevne maskiner bruger både lagerreferencer og aritmetiske
instruktioner fasen 'X'. Det afspejler at man i simple maskiner foretager
adresseberegning med den samme hardware som man bruger til aritmetiske
instruktioner. I standardmodellen har man i stedet en dedikeret fase til
adresseberegning, kaldet 'A'. Denne skelnen mellem 'A' og 'X' gør at man kan
begrænse 'A' til at forekomme i instruktionsrækkefølge, mens de andre
beregninger ikke har den begrænsning.

Instruktioner der skriver til lageret har et væsentlig mere kompliceret
forløb i en out-of-order maskine sammenlignet med en inorder maskine. 
Disse instruktioner må ikke opdatere lageret før 'C', så i stedet
placeres skrivningerne i en skrive-kø. Skrive-køen indeholder adresse
og data som kan bruges til at udføre skrivningen senere, efter 'C'.
Instruktioner indføjes i skrivekøen umiddelbart efter 'A'. Da 'A' er
en fase der udføres i instruktionsrækkefølge, kan efterfølgende instruktioner
der læser fra lageret sammenligne deres adresse med udestående skrivninger
i skrive-køen, og hvis adressen matcher kan den tilsvarende værdi hentes
fra skrive-køen. Instruktioner der skriver til lageret kan (skal) indsætte
deres adresse i skrive-køen selvom den værdi der skal skrives endnu ikke
er beregnet. Det tidspunkt hvor værdien kopieres til skrive-køen markeres 'V'.

### En lille out-of-order model

Her er en model af en lille out-of-order maskine
~~~
aritmetik:  F----QXC
movq (a),b: F----QAM--C
movq b,(a): F----QAMVC

dataafhængigheder:
aritmetik a op b: X.time >= max(a.time, b.time); b.time = X.time + 1
movq (a),b: A.time >= a.time; M.time >= MEM[a].time; b.time = M.time + 3
movq b,(a): A.time >= a.time, V.time >= b.time; MEM[a].time = V.time + 1

inorder(F,Q,C,A)
outoforder(X,M)
resB: max pr clk: F:2, Q:2, X:2, A:1, M:1, V:1, C:2
resC: max pr clk: F-Q: 8, M-W: 2, Q-C: 32
resD: unbounded: Q-X, Q-A, A-M, M-V, V-C, M-C
~~~
Bemærk at udover at faserne X og M nu er erklæret out-of-order, så er
der indsat en begrænsning på 32 instruktioner fra Q til C. Det vil sige
vi tillader 32 instruktioner at være i forskellige faser mellem Q og C.
Dette kaldes skeduleringsvinduet. Jo større det er, jo flere instruktioner
kan maskinen "se fremad" i instruktionsstrømmen.

Bemærk også at til forskel fra alle de tidligere maskiner er der ikke
længere noget krav om X skal følge i en bestemt afstand efter Q, eller
at C skal følge i en bestemt afstand efter X eller M.

Disse begrænsninger ville give følgende udførelse
~~~
                 012345678901234567
movq (r10),r11   F----QAM--C            r11.time = 10
addq $100,r11    F----Q----XC           r11.time = 11
movq r11,(r10)    F----QAM--VC          X.time >= r10.time, V.time >= r11.time
addq $8,r10       F----QX----C          r10.time = 8
movq (r10),r11     F----QAM---C         X.time >= r10.time, r11.time = 12
addq $100,r11      F----Q----XC         X.time >= r11.time, r11.time = 13
movq r11,(r10)      F----QAM--VC        X.time >= r10.time, V.time >= r11.time
addq $8,r10         F----QX----C        r10.time = 10
~~~
Med en gennemsnitlig ydeevne på 2 IPC.


# Kontrol afhængigheder

## Modellering

Vi modellerer effekten af hop, kald og retur ved at forsinke 'F'.
For kald og retur skelner vi mellem korrekte og fejlagtige
forudsigelser. For betingede hop skelner vi tillige mellem om
hoppet tages eller ej.

Vi udtrykker effekten ved tildelinger til en ny tidsvariabel: NextF.time
Og for enhver instruktion gælder altid at F.time >= NextF.time

Vi tilføjer en ny fase, 'B', specifik for betingede hop, kald og retur.
'B' svarer til 'X' for de aritmetiske instruktioner. 'B' angiver det
tidspunkt, hvor vi *afgør* om forudsigelser af instruktionen var korrekt
eller ej. Vi tillader at 'B' indtræffer out-of-order i forhold til andre 
typer instruktioner, men kræver det sker in-order i forhold til andre
hop, kald eller retur.

~~~
call a,b:   F----QBC
ret  a:     F----QBC
cbcc a,b,x: F----QBC
inorder(B)
~~~

Her er nogle mulige regler for en out-of-order maskine som beskrevet ovenfor
~~~
Instruktion  Taget  Forudsagt    Effekt
Call         ja     ja           NextF.time = F.time + 2
Ret          ja     ja           NextF.time = F.time + 2
             ja     nej          NextF.time = B.time + 1
CBcc         nej    ja           - (ingen)
             nej    nej          NextF.time = B.time + 1
             ja     ja           NextF.time = F.time + 2
             ja     nej          NextF.time = F.time + 2
~~~
Herunder ses to gennemløb af en indre løkke, hvor hop forudsiges korrekt.
~~~
                       012345678901234567
loop: movq (r10),r11   F----QAM--C            r11.time = 10
      addq $100,r11    F----Q----XC           r11.time = 11
      movq r11,(r10)    F----QAM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10       F----QX----C          r10.time = 8
      cbl  r10,r12,loop  F----QB----C             NextF.time = 4 (forudsagt korrekt taget)
loop: movq (r10),r11       F----QAM--C            r11.time = 14
      addq $100,r11        F----Q----XC           r11.time = 15
      movq r11,(r10)        F----QAM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10           F----QX----C          r10.time = 12
      cbl  r10,r12,loop      F----QB----C
~~~
Ydeevne: 5/4 IPC

På grund af omkostningen ved hop vil en compiler ofte rulle en løkke-krop
ud en eller flere gange. Herunder ses effekten af en enkelt udrulning

~~~
                       012345678901234567
loop: movq (r10),r11   F----QAM--C            r11.time = 10
      addq $100,r11    F----Q----XC           r11.time = 11
      movq r11,(r10)    F----QAM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10       F----QX----C          r10.time = 8
      cbgt  r10,r12,exit F----QB----C         forudsagt korrekt ikke taget
      movq (r10),r11     F----QAM---C         r11.time = 13
      addq $100,r11       F----Q----XC        r11.time = 14
      movq r11,(r10)      F----QAM--VC        X.time >= r10.time, V.time >= r11.time
      addq $8,r10          F----QX----C       r10.time = 11
      cbl  r10,r12,loop    F----QB----C       NextF.time = 6 (forudsagt korrekt taget)
loop: movq (r10),r11         F----QAM--C      r11.time = 16
~~~
Ydeevne: 10/6 IPC

En anden teknik til at skjule omkostningen ved tagne hop er at man dimensionerer
forenden af mikroarkitektur (F til Q) lidt større end resten. Her er for eksempel
et afviklingsplot for den ikke udrullede løkke på en maskine der kan håndtere 3
instruktioner samtidigt i F til Q:

~~~
                       012345678901234567
loop: movq (r10),r11   F----QAM--C            r11.time = 10
      addq $100,r11    F----Q----XC           r11.time = 11
      movq r11,(r10)   F----Q-AM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10       F----QX----C          r10.time = 8
      cbl  r10,r12,loop F----Q-B----C            NextF.time = 3 (forudsagt korrekt taget)
loop: movq (r10),r11      F----QAM--C            r11.time = 14
      addq $100,r11       F----Q----XC           r11.time = 15
      movq r11,(r10)      F----Q-AM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10          F----QX----C          r10.time = 12
      cbl  r10,r12,loop    F----Q-B----C
~~~
Ydeevne: 5/3 IPC

Her ses effekten af en forkert forudsigelse:
~~~
                       012345678901234567
loop: movq (r10),r11   F----QAM--C            r11.time = 10
      addq $100,r11    F----Q----XC           r11.time = 11
      movq r11,(r10)    F----QAM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10       F----QX----C          r10.time = 8
      cbl  r10,r12,loop  F----QB----C         NextF.time = 9 (forudsagt forkert)
loop: movq (r10),r11            F----QAM--C            r11.time = 14
      addq $100,r11             F----Q----XC           r11.time = 15
      movq r11,(r10)             F----QAM--VC          X.time >= r10.time, V.time >= r11.time
      addq $8,r10                F----QX----C          r10.time = 12
~~~
Ydeevne 5/9 IPC

Jo længere pipeline, jo større omkostning ved forkerte forudsigelser.


## spekulativ udførelse

Det kan ske at 'B' fasen indtræffer meget sent i forhold til udførelsen
af andre instruktioner. Betragt for eksempel nedenstående stump kode
~~~
    long v = tab[j];
    if (v > key) {
      *ptr = *ptr + 1; // found it!
    }
~~~
Oversat til x86prime kan det blive til følgende programstump:
~~~
        movq (r10,r11,8),r12
        cble r12,r13,.endif
        movq (r15),r14
        addq $1,r14
        movq r14,(r15)
.endif:
~~~
og lad os antage at variablen 'tab' befinder sig i L2-cache, mens området
udpeget af variablen 'ptr' er i L1-cache. Lad os antage at L2-cache tilgang
koster 10 cykler (oveni L1-tilgang).
~~~
                              01234567890123456789012
        movq (r10,r11,8),r12  F----QAM------------C
        cble r12,r13,else     F----Q--------------BC
        movq (r15),r14         F----QAM------------C
        addq $1,r14            F----Q----X----------C
        movq r14,(r15)          F----QAM--V---------C
~~~
Det betingede hop afhænger af en instruktion der er nød til at hente en værdi
i L2 og bliver således forsinket så det først kan afgøres i cyklus 20.

Hoppet er forudsagt "ikke taget" og før det afgøres kan de næste tre instruktioner
læse fra L1-cachen, beregne en ny værdi og lægge den i kø til skrivning til L1.

Det går selvsagt ikke an faktisk at opdatere L1, før vi ved om hoppet er
forudsagt korrekt, men alle øvrige aktiviteter kan gennemføres. De instruktioner
som udføres tidligere end et eller flere hop, kald eller retur, som de egentlig
afhænger af, siges at være spekulativt udført. Spekulativ udførelse fjerner en
væsentlig begrænsning på hvor meget arbejde der kan udføres parallelt.

