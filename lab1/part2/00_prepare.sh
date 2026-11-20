#!/bin/bash
# Подготовка к части 2: администратор, включение аутентификации, учебные базы.
# Запуск от root: ./00_prepare.sh 
set -e
if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root (su -)"; exit 1; fi

A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"

if grep -Eq '^\s*authorization:\s*enabled' /etc/mongod.conf; then
  echo "Аутентификация уже включена"
else
  echo "Создание администратора admin"
  mongosh --quiet --eval 'db.getSiblingDB("admin").createUser({user:"admin", pwd:"Admin_123", roles:[{role:"root", db:"admin"}]})'
  echo "Включение аутентификации"
  printf '\nsecurity:\n  authorization: enabled\n' >> /etc/mongod.conf
  systemctl restart mongod
  sleep 3
fi

echo "Создание учебных баз shop, school, library"
mongosh --quiet "$A" --eval '
  const mk = (d, c, n, f) => { const col = db.getSiblingDB(d)[c]; col.drop();
    const a = []; for (let i = 1; i <= n; i++) a.push(f(i)); col.insertMany(a); print(d + "." + c + ": " + n); };
  mk("shop", "customers", 20, i => ({_id: i, name: "Клиент " + i}));
  mk("shop", "orders", 50, i => ({_id: i, customerId: 1 + i % 20, total: 100 * i}));
  mk("school", "students", 20, i => ({_id: i, name: "Студент " + i}));
  mk("school", "grades", 100, i => ({_id: i, studentId: 1 + i % 20, mark: 2 + i % 4}));
  mk("library", "books", 20, i => ({_id: i, title: "Книга " + i}));'
echo "Готово"
