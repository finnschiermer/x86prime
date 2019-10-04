# Superskalar mikroarkitektur

I jagten efter højere ydeevne kan man finde på at skrue op for ressourcerne.
Hvis der er mere end en instruktion der udfører sin `X`-fase samtidigt, taler
man om en superskalar maskine.
Det er en naturlig følge af en simpel pipeline arkitektur, og de første superskalar arkitekturer kom da også kort efter disse. Valget af `X` fasen skyldes den indsigt at denne fase er særligt meget brugt og ofte af instruktioner som ikke har en dataafhængighed. Men for at have flere instruktioner er man også nødt til at udvide andre dele af arkitekturen.

En simpel 2-vejs superskalar kan derfor håndtere to instruktioner samtidigt i
faserne `F`,`D`,`X` og `W`, men kun 1 instruktion samtidigt i fase `M`. Det er motiveret
af at fase `M` er dyrere end de andre. Tilgengæld kan man knytte en delmængde af de mulige faser
til forskellige klasser af instruktioner: f.eks. det er således at ikke alle har en fase `M`.
Man kan også undgå en fase `W` for instruktioner der ikke skriver til et resultat
registerfilen.

## Eksempel: Superskalar

Faser:

* Tilgængelige ressourcer: `F:2`, `D:2`, `X:2`, `M:1`, `W:2`
* Alle faser tager har en latenstid på 1
* `inorder(F,D,X,M,W)`


Begrænsninger på instruktioner:

|           | Instruktion  | Faser   | Dataafhængigheder                        |
|-----------|--------------|---------|------------------------------------------|
| Aritmetik | `op  a b`    | `FDXW`  | `depend(X,a), depend(X,b), produce(M,b)` |
| Læsning   | `movq (a),b` | `FDXMW` | `depend(X,a), produce(W,b)`              |
| Skrivning | `movq b,(a)` | `FDXM`  | `depend(X,a), depend(M,b)`               |

Overvej afviklingen af følgende program:

~~~ text
                 012345678      -- Vigtige dataafhængigheder
movq (r10),r11   FDXMW          -- produce(W,r11)
addq $100,r11    FDDDXW         -- depend(X,r11), produce(M,r11)
movq r11,(r10)    FDDXM         -- depend(M,r11)
subq $8,r10       FFFDXW        --
~~~

0. periode: Nu kan vi indhente og afkode både første og anden instruktion
1. periode: Begge instruktioner flyttes til afkodning og de to næste bliver indhentet. Her finder vi ud af at der er en dataafhængighed mellem de to første og sikre at anden instruktion blive stalled i `D`.
2. periode: Tredje instruktion (skrivning) flyttes til afkodning, men `subq` bliver stalled i `F`, da der ikke er plads i `D`.
3. periode: Sker ikke noget nyt.
4. periode: Læsningen er færdig og alle instruktioner kan flyttes frem. Skrivningen behøver ikke at blive stalled, da afhængigheden til `r11` først er i fase `M`.
5. periode og frem forløber som forventet.

Hvis vi igen kigger på søjlerne i plottet, har ingen af disse flere forekomster af faserne end vi har ressourcer  til rådighed. Der er altså højst 2 `F`'er, `D`'er osv., men kun højest et `M`. Dertil ser vi at søjlerne oppefra lister faserne bagfra og vi ved derfor at disse bliver udført in-order.


## Eksempel 2: Kontrolafhængighed



&nbsp;