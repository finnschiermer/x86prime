## Pipeline faser og ressourcer

Siden slutningen af 70'erne hvor de første pipeline arkitekturer blev introduceret, har en instruktion gennemgået flere faser når den afvikles. Nogle faser er generiske; nogle afhænger af instruktionen.

Faserne gennemløbes i rækkefølge bestemt af instruktionstype og mikroarkitektur.

Betragt for eksempel en afviklingen på en simpel pipeline, typisk for de første RISC
maskiner konstrueret i 80'erne. Her er der fem faser:

* `F`: Fetch, indlæsning af instruktionen fra hukommelse,
* `D`: Decode, afkodning af instruktionen og udlæsning fra registerfil,
* `X`: eXecute, udførsel af aritmetisk/logisk operation, samt beregning af mulig adresse,
* `M`: Memory, læsning fra eller skrivning til hukommelsen,
* `W`: Writeback, tilbageskrivning til registerfilen.

Her ses nogle begrænsninger for en 5-trins pipeline:

* Alle instruktioner gennemløber: `FDXMW`
* Tilgængelige ressourcer: `F:1`, `D:1`, `X:1`, `M:1`, `W:1`

Ovenstående skal læses som: alle instruktioner passerer gennem samtlige fem trin ordnet som beskrevet; det findes en ressource for hvert trin, altså der kan kun være en instruktion i hver trin.

Bemærk at det er en voldsom forenkling at udtrykke begrænsningen for
instruktionshentning i et antal instruktioner. Især hvis instruktionen kommer til at ligge over to cache linier. For en maskine med instruktioner
af forskellig længde er bindingen mere korrekt udtrykt som et antal bytes.
Først i forbindelse med afkodning er det klart, hvor en instruktion begynder
og slutter. Den lille detalje vil vi se bort fra.

### Eksempel: Simpel pipeline mikroarkitektur

For eksempel vil afviklingsplottet for et mindre udvidet eksempel program, vil være følgende:
~~~
                 012345678
movq (r10),r11   FDXMW
mulq r10,r12      FDXMW
addq $100,r13      FDXMW
movq r14,(r10)      FDXMW
subq $1,r10          FDXMW
~~~
Her ses at første instruktion bliver indhentet i første clock periode. I anden clock periode vil anden instruktion blive indhentet samtidig med at første instruktion bliver afkodet, osv.

Det er vigtigt at vi overholde begrænsningerne. For at tjekke det ser vi at:
* første begrænsning bliver overholdt, da alle linier i plottet indeholder alle fem trin, og
* anden begrænsning bliver overholdt da hver søjle (clock periode) kun indeholder hvert trin en gang.

Hvis vi prøver at udregne ydeevnen for programmet, kan vi se at det samlet bruger 8 clock perioder: antallet af instruktioner + antallet af trin - 1. Hvis vi sammenligner med vores enkelt-cyklus maskine, er dette næsten så mange clock perioder, men en periode vil også være signifikant kortere; dog ikke så lav som en femtedel.


## Latenstid af faser
På en pipeline arkitektur bruger instruktioner en eller flere clock-perioder
til at producere et resultat. Det kaldes instruktionens latenstid. Latenstiden
er den tid der går fra instruktionen modtager/fremfinder sin sidste indgående operand
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

### Eksempel: Latenstid
Lad os undersøge en pipeline maskine og definerer latenstiden i clock perioder (delay) for instruktionerne som:

* Simpel aritmetik `op  a b`:    `delay(X)=1`
* Multiplikation   `mul a b`:    `delay(X)=4`
* Læsning          `movq (a),b`: `delay(M)=2`
* Skrivning        `movq b,(a)`: `delay(M)=2`
* Alle øvrige faser tager har en latenstid på 1

Husk vi har stadig:

* Alle instruktioner gennemløber: `FDXMW`
* Tilgængelige ressourcer: `F:1`, `D:1`, `X:1`, `M:1`, `W:1`

Det tidligere eksempel, vil nu blive
~~~
                           111
                 0123456789012
movq (r10),r11   FDXMMW
mulq r10,r12      FDXXXXMW
addq $100,r13      FDDDDXMW
movq r14,(r10)      FFFFDXMMW
subq $1,r10             FDXXMW
~~~
Da vi i første instruktion læser fra hukommelsen, vil `M` fasen nu tage to cykler. Det samme ses for anden instruktion, der nu bliver i `X` fasen i fire clock perioder.

Tredje instruktion er tilgengæld mindre åbenlys. Vi skal stadig overholde de to begrænsninger fra tidligere. Specifikt kan `addq` instruktionen ikke begynde `X` fasen før `mulq` er færdig. Derfor laves en forsinkelse ("stall"), som sikre `addq` bliver i `D` fasen. På samme måde er vi nødt til at forsinke skrivningen i fjerde instruktion ved at stalle den i `F`.

Indlæsningen af sidste instruktion, `subq`, kan derfor ikke begyndes før clock periode nummer 7, når `F` frigives fra den tidligere instruktion. Læg også mærke til at instruktionen er nødt til at stalle i `X`.

Igen ser vi at:

* alle linier i plottet indeholder alle fem trin mindst en gang, og
* hver søjle (clock periode) kun indeholder hvert trin en gang.

Vi kan igen prøver at udregne ydeevnen for programmet og se at det samlet bruger 13 clock perioder. Igen bliver det flere perioder hvis vi sammenligner med den simple pipeline, men igen kan vi forvente en lavere clock periode.


## Data afhængigheder og forwarding
Mere signifikant end latenstiden er data afhængigheder. Det har ikke været et problem i vores tidligere eksempler (ikke en tilfældighed), men kan hurtigt blive det for normale programmer.

Overvej følgende program:
~~~
movq (r10),r11
addq $100,r11
movq r11,(r10)
addq $8,r10
subq $1,r12
~~~

Her bliver både register `r11` opdateret i instruktionen lige før det bliver læst; endda to gange. F.eks. indlæser første instruktion en værdi til `r11`, som anden instruktion staks lægger noget til; men også fra anden til tredje instruktion. Vi kan lave data-flow graph, som beskrevet i CSapp, som vil tydeliggøre de data afhængigheder, som eksisterer i programmet. Instruktionsnummeret er indsat efter navnet.

~~~ text
    r10  r11   r12
      | \ |     |
      | movq1   |
      |   |     |
      | addq2   |
      | / |     |
    movq3 |     |
      |   |     |
    addq4 |    subq5
      |   |     |
    r10  r11   r12

~~~

Hvis vi laver et simple afviklingsplot som før, vil vi få følgende:
~~~
movq (r10),r11  FDXMMW
addq $100,r11    FDXXMW
movq r11,(r10)    FDDXMMW
addq $8,r10        FDDXXMW
subq $1,r12         FFDDXMW
(OVENSTÅENDE VIRKER IKKE)
~~~

Ud over den tydelige tekst, som indikerer det, kan vi overbevise os selv om at ovenstående ikke virker. Vi har en data afhængighed mellem læsningen og først addition og vi ved fra ovenstående den tidligere uformelle beskrivelse at læsning fra hukommelse sker i `M`fasen. Men i plottet laver vi additionen i `X` samtidig med `M`; altså før vi har værdien til rådighed.

For at undgå dette er vi nødt til at tilføje afhængighederne til vores instruktioner. Det kan vi skrive på følgende måde:

* Aritmetik   `op  a b`:    `depend(X,a), depend(X,b), produce(X,b)`
* Læsning     `movq (a),b`: `depend(X,a), produce(M,b)`
* Skrivning   `movq b,(a)`: `depend(X,a), depend(M,b)`

Her står at aritmetiske instruktioner er afhængig er at værdierne for både `a` og `b` er klar til fase `X`, samt at de producerer deres resultat til register `b` i slutningen af fase `X`.
Læsning fra hukommelsen kræver at adressen der skal læses fra register `a` er klar til fase `X` (husk at vi har beregningen af adressen i `X` fasen, selvom læsningen først foregår i `M` fasen), mens resultatet er læsningen til register `b` er klar efter fase `M`.
Ved Skrivning til hukommelsen skal adressen i register `a` er klar til fase `X`, mens værdien først skal være klar til fase `M`. Skrivning til hukommelsen har ikke noget resultat.

Vær opmærksom på at ovenstående implementerer en arkitektur med fuld forwarding. Altså at alle værdier kan bruges umiddelbart i næste clock periode i alle efterfølgende instruktioner; dvs. før de reelt set er skrevet tilbage til registerfilen.
Hvis vi i stedet ville have en maskine uden forwarding, ville alle værdier bliver produceret til fase `W`, hvor vi reelt skriver værdien tilbage.

### Eksempel: Data afhængigheder
Lad os nu definerer det korrekt afviklingspot for eksemplet. Først, lad os dog opsummerer alt vi har defineret for maskinen:

* Tilgængelige ressourcer: `F:1`, `D:1`, `X:1`, `M:1`, `W:1`

|             | Instruktion    | Faser     | Dataafhængigheder                          |
| ----------- | -------------- | --------- | ------------------------------------------ |
| Aritmetik   | `op  a b`      | `FDXMW`   | `depend(X,a), depend(X,b), produce(X,b)`   |
| Læsning     | `movq (a),b`   | `FDXMW`   | `depend(X,a), produce(M,b)`                |
| Skrivning   | `movq b,(a)`   | `FDXMW`   | `depend(X,a), depend(M,b)`                 |


* Simpel aritmetik `op  a b`:    `delay(X)=1`
* Multiplikation   `mul a b`:    `delay(X)=4`
* Læsning          `movq (a),b`: `delay(M)=2`
* Skrivning        `movq b,(a)`: `delay(M)=2`
* Alle øvrige faser tager har en latenstid på 1

~~~
                 01234567890     -- Beskrivelse
movq (r10),r11   FDXMMW          -- produce(M,r11)
addq $100,r11     FDDDXMW        -- depend(X,r11), produce(X,r11), stall i D
movq r11,(r10)     FFFDXMMW      -- Stall i F, depend(X,r11)
addq $8,r10           FDXXMW     -- Forsinket F
subq $1,r12            FDDXMW    --
~~~


Bemærk hvorledes instruktion nr. 2 bliver forsinket en clock periode i sin `D`-fase,
fordi den afhænger af `r11` som bliver produceret af den forudgående instruktion
der har en latenstid på 2 clock-perioder.

## In-order udførsel af instruktioner
Men hov! Vi har lige fundet ud af at sidste instruktion ikke har dataafhængigheder til de øvrige, så hvorfor kan vi ikke spare en clock periode ved at lave:
~~~
                 01234567        -- Beskrivelse
movq (r10),r11   FDXMMW          -- produce(M,r11)
addq $100,r11      FDDXMW        -- depend(X,r11), produce(X,r11), stall i D
movq r11,(r10)      FFFDXMMW     -- Stall i F, depend(X,r11)
addq $8,r10            FDXXMW    -- Forsinket F
subq $1,r12       FDXXMW         --
~~~
Vi har måske lidt svært ved at se, hvordan en maskine overhovedet skulle
kunne konstrueres således at ovenstående afviklingsrækkefølge kunne finde sted og en maskine er nødt til at læse instruktionerne i den rækkefølge, som er specificeret i vores program.

Vi indfører derfor en begrænsning mere: Hver fase gennemføres i instruktionerne i rækkefølge.
~~~
inorder(F,D,X,M,W)
~~~
Vi har overholdt dette i tidligere eksempler. Vi kan tjekke det ved at når vi læser hver søjle oppefra, skal vi se faserne bagfra.

Det er dog noget som vores oversætter kan håndterer, ved at flytte sidste instruktion frem. Dermed kan vi opnå ovenstående udførsel:

~~~
                 01234567        -- Beskrivelse
                 01234567        -- Beskrivelse
movq (r10),r11   FDXMMW          -- produce(M,r11)
subq $1,r12       FDXXMW         --
addq $100,r11      FDDXMW        -- depend(X,r11), produce(X,r11), stall i D
movq r11,(r10)      FFFDXMMW     -- Stall i F, depend(X,r11)
addq $8,r10            FDXXMW    -- Forsinket F
~~~


## Kontrolafhængigheder




&nbsp;