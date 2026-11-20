#!/bin/bash
# Пункт 3. Назначение ролей пользователю ann и их отзыв, с проверкой прав.
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
adm() { mongosh --quiet "$A" --eval "$1"; }
roles() { adm 'print("  роли ann: " + (db.getSiblingDB("school").getUser("ann").roles.map(r => r.role).join(", ") || "(нет)"))'; }
# проверка от имени ann: try "описание" "команда"
try() {
  r=$(mongosh --quiet "mongodb://ann:Pass_123@127.0.0.1:27017/school?authSource=school" \
      --eval "try { $2; print('РАЗРЕШЕНО') } catch (e) { print('ЗАПРЕЩЕНО') }" 2>&1 | tail -1)
  printf '  %-40s %s\n' "$1" "$r"
}

echo "Сейчас"; roles
try "чтение students" 'db.students.findOne()'

echo; echo "Назначаем роль reader"
adm 'db.getSiblingDB("school").grantRolesToUser("ann", [{role:"reader", db:"school"}])'
roles
try "чтение students" 'db.students.findOne()'
try "запись в grades" 'db.grades.insertOne({_demo:1})'

echo; echo "Назначаем роль grader"
adm 'db.getSiblingDB("school").grantRolesToUser("ann", [{role:"grader", db:"school"}])'
roles
try "запись в grades" 'db.grades.insertOne({_demo:1})'

echo; echo "Отзываем роль grader"
adm 'db.getSiblingDB("school").revokeRolesFromUser("ann", [{role:"grader", db:"school"}])'
roles
try "запись в grades" 'db.grades.insertOne({_demo:2})'
try "чтение students (reader остался)" 'db.students.findOne()'

adm 'db.getSiblingDB("school").grades.deleteMany({_demo: {$exists: true}})' > /dev/null
echo; echo "Готово"
