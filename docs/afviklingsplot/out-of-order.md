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

Vi kan ane at der findes mere ydeevne i form af mere parallelisme i udførelsen, hvis vi
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

Og vi benytter lejligheden til at fjerne `W` trinnet fra beskrivelsen.

### Lagerreferencer

I de hidtil beskrevne maskiner bruger både lagerreferencer og aritmetiske
instruktioner fasen `X`. Det afspejler at man i simple maskiner foretager
adresseberegning med den samme hardware som man bruger til aritmetiske
instruktioner. I standardmodellen har man i stedet en dedikeret fase til
adresseberegning, kaldet `A`. Denne skelnen mellem `A` og `X` gør at man kan
begrænse `A` til at forekomme i instruktionsrækkefølge, mens de andre
beregninger ikke har den begrænsning.

Instruktioner der skriver til lageret har et væsentlig mere kompliceret
forløb i en out-of-order maskine sammenlignet med en inorder maskine.
Disse instruktioner må ikke opdatere lageret før `C`, så i stedet
placeres skrivningerne i en skrive-kø. Skrive-køen indeholder adresse
og data som kan bruges til at udføre skrivningen senere, efter `C`.
Instruktioner indføjes i skrivekøen umiddelbart efter `A`. Da `A` er
en fase der udføres i instruktionsrækkefølge, kan efterfølgende instruktioner
der læser fra lageret sammenligne deres adresse med udestående skrivninger
i skrive-køen, og hvis adressen matcher kan den tilsvarende værdi hentes
fra skrive-køen. Instruktioner der skriver til lageret kan (skal) indsætte
deres adresse i skrive-køen selvom den værdi der skal skrives endnu ikke
er beregnet. Det tidspunkt hvor værdien kopieres til skrive-køen markeres ` V`.

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


