# Superskalar mikroarkitektur

I jagten efter højere ydeevne kan man finde på at skrue op for ressourcerne.
Hvis der er mere end en instruktion der udfører sin `X`-fase samtidigt, taler
man om en superskalar maskine.
Det er en naturlig følge af en simpel pipeline arkitektur, og de første superskalar arkitekturer kom da også kort efter disse. Valget af `X` fasen skyldes den indsigt at denne fase er særligt meget brugt og ofte af instruktioner som ikke har en dataafhængighed. Men for at have flere instruktioner er man også nødt til at udvide andre dele af arkitekturen.

En simpel 2-vejs superskalar kan håndtere to instruktioner samtidigt i
faserne `F`,`D`,`X` og `W`, men kun 1 instruktion samtidigt i fase `M`. Det er motiveret
af at fase `M` er dyrere end de andre. Tilgengæld kan man knytte forskellige faser
til forskellige klasser af instruktioner, således at ikke alle har en fase `M`.
Man kan også undgå en fase `W` for instruktioner der ikke skriver til et resultat
register.


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

