#!/bin/bash
# Пункт 4. Изменение набора операций у существующей роли grader (коллекция grades).
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
adm() { mongosh --quiet "$A" --eval "$1"; }
show() { adm 'const r = db.getSiblingDB("school").getRole("grader", {showPrivileges:true});
  print("  grader: " + r.privileges.map(p => p.resource.collection + " [" + p.actions.join(",") + "]").join("; "))'; }
try() {
  r=$(mongosh --quiet "mongodb://ann:Pass_123@127.0.0.1:27017/school?authSource=school" \
      --eval "try { $2; print('РАЗРЕШЕНО') } catch (e) { print('ЗАПРЕЩЕНО') }" 2>&1 | tail -1)
  printf '  %-40s %s\n' "$1" "$r"
}

# ann должна иметь роль grader
adm 'db.getSiblingDB("school").grantRolesToUser("ann", [{role:"grader", db:"school"}])' > /dev/null

echo "Исходный набор"; show
try "запись в grades" 'db.grades.insertOne({_demo:1})'
try "удаление из grades" 'db.grades.deleteMany({_demo:1})'

echo; echo "Добавляем операцию remove (grantPrivilegesToRole)"
adm 'db.getSiblingDB("school").grantPrivilegesToRole("grader", [{resource:{db:"school",collection:"grades"}, actions:["remove"]}])'
show
try "удаление из grades" 'db.grades.deleteMany({_demo:1})'

echo; echo "Заменяем набор целиком на find (updateRole)"
adm 'db.getSiblingDB("school").updateRole("grader", {privileges:[{resource:{db:"school",collection:"grades"}, actions:["find"]}]})'
show
try "чтение grades" 'db.grades.findOne()'
try "запись в grades" 'db.grades.insertOne({_demo:2})'

echo; echo "Возвращаем исходный набор find, insert, update"
adm 'db.getSiblingDB("school").updateRole("grader", {privileges:[{resource:{db:"school",collection:"grades"}, actions:["find","insert","update"]}]})'
show

adm 'db.getSiblingDB("school").grades.deleteMany({_demo: {$exists: true}})' > /dev/null
echo; echo "Готово"
