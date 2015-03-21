# entête du fichier collecteur d'erreurs
# code_insee: code_insee indiqué dans le fichier d'origine
# id: id BAN de l'adresse à vérifier/corriger
# champs: liste des champs concernés séparés par '+'
# contenu: contenu du premier champ concerné
# erreur: descriptif textuel de l'erreur
# echo 'code_insee,id,champs,contenu,erreur' > erreurs.csv

# chaine de connexion à la base postgres locale
DB=postgresql:///cquest

echo "\n-- nombre de nom_voie vides ou nuls sans nom_ld (regroupés par département)\n"
psql -P pager -c "select left(code_insee,2) as dept, count(*) as nb_nom_vide, sum(case when id_fantoir!='' then 1 else 0 end) as avec_fantoir from ban_temp where nom_voie='' and nom_ld='' group by 1 order by 1;"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie+nom_ld','','nom_voie et nom_ld vide' from ban_temp where nom_voie='' and nom_ld=''" >> erreurs.csv

echo "\n-- nom_voie contient nom_ld\n"
sql2csv --db "$DB" -H --query "select b.code_insee, b.id, 'nom_voie+nom_ld',b.nom_voie,'nom_voie contient nom_ld' from ban_temp b join ban_temp c on (c.id=b.id) where b.nom_voie !='' and c.nom_ld !='' and lower(unaccent(b.nom_voie)) like '%' || lower(unaccent(c.nom_ld)) || '%'" >> erreurs.csv


echo "\n-- nombre de nom_voie avec '/' (regroupés par département)\n"
psql -P pager -c "select left(code_insee,2) as dept, count(*) as nb, min(nom_voie) as exemple from ban_temp where nom_voie like '%/%' group by 1 order by 1;"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'nom_voie contient /' from ban_temp where nom_voie ~ '\/'" >> erreurs.csv

echo "\n-- nombre de nom_voie avec '/' et répétitions (regroupés par département)\n"
psql -P pager -c "select left(code_insee,2) as dept, count(*) as nb_total, sum(repete) as nb_repete, min(nom_voie) as exemple from (select code_insee, nom_voie, array_length(regexp_matches(nom_voie,'^(.*)/\1$'),1) as repete from ban_temp where nom_voie like '%/%') as r group by 1 order by 1;"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'nom_voie contient / avec valeurs repetees' from ban_temp where nom_voie ~ '^(.*)/\1$' " >> erreurs.csv

echo "\n-- nombre de nom_voie différents avec id_fantoir identique (regroupés par département)\n"
psql -P pager -c "select left(code_insee,2) as dept, count(*) as nb, min(noms) as exemple from (select code_insee, id_fantoir, count(*) as nb_noms, sum(nb) as nb_adresses, left(string_agg(nom,' + '),100) as noms from (select code_insee, id_fantoir, format('"%s,%s"',nom_voie,nom_ld) as nom, count(*) as nb from ban_temp where id_fantoir !='' group by 1,2,3) as f group by 1,2) as f2 where nb_noms>1 group by 1 order by 1;"

echo "\n-- exemples de nom_voie différents avec id_fantoir identique\n"
psql -P pager -c "select code_insee, id_fantoir, count(*) as nb_noms, sum(nb) as nb_adresses, left(string_agg(nom,' + '),100) as noms from (select code_insee, id_fantoir, format('"%s,%s"',nom_voie,nom_ld) as nom, count(*) as nb from ban_temp where id_fantoir !='' group by 1,2,3) as f group by 1,2 order by 3 desc limit 50;"

echo "\n-- vérification erreurs courantes d'accentuation\n"
psql -P pager -c "select nom_voie, count(*) as nb from ban_temp where nom_voie ~ ' clémenceau( |$)' group by 1 order by 2 desc;"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'erreur accentuation' from ban_temp where nom_voie ~ ' clémenceau( |$)' " >> erreurs.csv

echo "\n-- vérification chiffres romains en minuscule\n"
psql -P pager -c "select nom_voie, count(*) as nb from ban_temp where nom_voie ~ ' [ivx]*( |$)' and nom_voie !~ 'vi?[vx]' group by 1 order by 2 desc;"

echo "\n-- vérification de présence d'abbréviations résiduelles\n"
for a in `csvcut ../data/abbrev.txt --columns 1 | tail -n +2 | tr '[:upper:]' '[:lower:]' | tr '_' '\ '`
do
echo "  abrev: $a"
psql -P pager -c "
select nom_voie, count(*) as nb, left(string_agg(distinct(code_insee),','),60) as exemple from ban_temp where nom_voie ~ '(^| )$a( |$)' group by 1 order by 2 desc;
" &
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'abbreviation residuelle: $a' from ban_temp where nom_voie ~ '(^| )$a( |$)' " >> erreurs.csv
done

echo "\n-- vérification de présence d'abbréviations doublées\n"
psql -P pager -c "
select nom_voie, count(*) from ban_temp where nom_voie ~ '(^| )(chemin .*chem|grand.*gde)( |$)' group by 1 order by 2 desc;
"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'abbreviation residuelle doublee' from ban_temp where nom_voie ~ '(^| )(chemin .*chem|grand.*gde)( |$)' " >> erreurs.csv

echo "\n-- noms très longs\n"
psql -P pager -c "
select length(nom_voie) as longueur, nom_voie, code_insee, id_fantoir from ban_temp where length(nom_voie)>60 group by 1,2,3,4 order by 1 desc limit 50;
"

echo "\n-- noms comportant des parenthèses\n"
psql -P pager -c "
select nom_voie, left(string_agg(code_insee,','),60) as exemple from ban_temp where nom_voie ~ '\(' or nom_voie ~ '\)' group by 1 order by 1;
"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'nom comportant des parentheses' from ban_temp where nom_voie ~ '\(' or nom_voie ~ '\)' " >> erreurs.csv

echo "\n-- noms comportant des tirets\n"
psql -P pager -c "
select nom_voie, left(string_agg(code_insee,','),60) as exemple from ban_temp where nom_voie ~ ' -' or nom_voie ~ '- ' or nom_voie ~ '--' group by 1 order by 1;
"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'nom comportant des tirets' from ban_temp where nom_voie ~ ' -' or nom_voie ~ '- ' or nom_voie ~ '--' " >> erreurs.csv

echo "\n-- noms comportant des caractères étranges\n"
psql -P pager -c "
select nom_voie, left(string_agg(code_insee,','),60) as exemple from ban_temp where nom_voie !~ '[a-z0-9\-\/\(\)]' group by 1 order by 1;
"
sql2csv --db "$DB" -H --query "select code_insee,id,'nom_voie',nom_voie,'nom comportant des caracteres non alpha-num' from ban_temp where nom_voie !='' and replace(lower(unaccent(nom_voie)),chr(39),'') ~ '[^a-z0-9\-\/\(\) °]'" >> erreurs.csv

