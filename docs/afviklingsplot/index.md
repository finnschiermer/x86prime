# Afviklings Plot (Execution graph)

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

### Eksempel: Enkelt-cyklus mikroarkitektur

Her er for eksempel afviklingen af 4 instruktioner på en enkelt-cyklus (single cycle) mikroarkitektur
~~~
                 0123
movq (r10),r11   X
mulq $100,r11     X
movq r1,(r10)      X
subq $1,r10         X
~~~
Her er kun en enkelt fase, kaldet `X` for eXecute, da alle instruktioner kan udføres på en enkelt clock-periode. Vi har altså den sekventielle model, som den vi forstår når vi læser et assembler program; altså først indlæser vi noget fra hukommelsen, derefter ligger vi en værdi til dette, hvorefter vi skriver det tilbage til hukommelsen.

Hvis vi ønsker at finde denne arkitekturs ydeevne, kan man altså gøre dette ved at tælle antallet af instruktioner; i ovenstående tilfælde altså 4 clock perioder.

&nbsp;
