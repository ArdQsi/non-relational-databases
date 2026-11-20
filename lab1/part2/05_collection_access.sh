#!/bin/bash
# Пункт 5. Доступ пользователя только к одной коллекции (shop.orders), без доступа ко всей базе.
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
try() {
  r=$(mongosh --quiet "mongodb://auditor:Pass_123@127.0.0.1:27017/shop?authSource=shop" \
      --eval "try { $2; print('РАЗРЕШЕНО') } catch (e) { print('ЗАПРЕЩЕНО') }" 2>&1 | tail -1)
  printf '  %-40s %s\n' "$1" "$r"
}

mongosh --quiet "$A" --eval '
  const d = db.getSiblingDB("shop");
  try { d.dropUser("auditor") } catch (e) {}
  try { d.dropRole("orders_reader") } catch (e) {}
  // роль с единственной привилегией: чтение коллекции orders
  d.createRole({role: "orders_reader", roles: [],
    privileges: [{resource: {db: "shop", collection: "orders"}, actions: ["find"]}]});
  d.createUser({user: "auditor", pwd: "Pass_123", roles: [{role: "orders_reader", db: "shop"}]});
  print("создан пользователь auditor с ролью orders_reader (только shop.orders, find)");'

echo; echo "Проверка от имени auditor"
try "чтение shop.orders" 'db.orders.findOne()'
try "чтение shop.customers" 'db.customers.findOne()'
try "запись в shop.orders" 'db.orders.insertOne({_demo:1})'
echo; echo "Готово"
