# Afviklings Plot

af Finn Schiermer Andersen, DIKU, 2019

Denne lille note introducerer afviklingsplot.

Et afviklingsplot er en idealiseret illustration af hvordan en mikroarkitektur
afvikler en strøm af instruktioner. Men det er også et redskab som kan bruges
til at bestemme en mikroarkitekturs ydeevne for en strøm af instruktioner.


## Idè

Under afvikling af hver instruktion på en given mikroarkitektur gennemgår
instruktionen forskellige faser. Et afviklingsplot angiver tidspunktet
for hver væsentlig fase en instruktion gennemløber. Instruktionsstrømmen
angives yderst til venstre, oppefra og ned. Tiden angives i clock-perioder fra
venstre mod højre.

Her er for eksempel afviklingen af 4 instruktioner på en enkelt-cyklus (single cycle) mikroarkitektur
~~~
                 0123
movq (r10),r11   X
addq $100,r11     X
movq r1,(r10)      X
addq $1,r10         X
~~~
Her er kun en enkelt fase, kaldet `X` for eXecute, da alle instruktioner kan udføres på en enkelt clock-periode. Vi har altså den sekventielle model, som den vi forstår når vi læser et assembler program; altså først indlæser vi noget fra hukommelsen, derefter ligger vi en værdi til dette, hvorefter vi skriver det tilbage til hukommelsen.

Hvis vi ønsker at finde denne arkitekturs ydeevne, kan man altså gøre dette ved at tælle antallet af instruktioner.


## Pipeline faser og ressourcer

Siden slutningen af 70'erne hvor de første pipeline arkitekturer blev introduceret, har en instruktion gennemgået flere faser når den afvikles. Nogle faser er generiske; nogle afhænger af instruktionen.

Faserne gennemløbes i rækkefølge bestemt af instruktionstype og mikroarkitektur.

Betragt for eksempel en afviklingen på en simpel pipeline, typisk for de første RISC
maskiner konstrueret i 80'erne. Her er der fem faser: `FDXMW` (Fetch, Decode, eXecute,
Memory, Writeback).

Alle instruktioner passerer gennem de samme fem trin.

Her ses nogle begrænsninger for en 5-trins pipeline:
~~~
alle instruktioner:  FDXMW
ressourcer: F:1, D:1, X:1, M:1, W:1
~~~
Bemærk at det er en voldsom forenkling at udtrykke begrænsningen for
instruktionshentning i et antal instruktioner. For en maskine med instruktioner
af forskellig længde er bindingen mere korrekt udtrykt som et antal bytes.
Først i forbindelse med afkodning er det klart, hvor en instruktion begynder
og slutter. Den lille detalje vil vi se bort fra.

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
og til en efterfølgende instruktion som afhænger af resultatet kan begynde
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
Bemærk hvorledes instruktion nr. 2 bliver forsinket en clock periode i sin `D`-fase,
fordi den afhænger af `r11` som bliver produceret af den forudgående instruktion
der har en latenstid på 2 clock-perioder.


