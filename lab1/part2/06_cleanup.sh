#!/bin/bash
# Пункт 6. Удаление ролей и пользователей, созданных в части 2.
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"

mongosh --quiet "$A" --eval '
  const s = db.getSiblingDB("school"), h = db.getSiblingDB("shop"), l = db.getSiblingDB("library");
  const show = () => print("  school: пользователи [" + s.getUsers().users.map(u => u.user) + "], роли [" + s.getRoles().roles.map(r => r.role) + "]\n" +
                           "  shop:   пользователи [" + h.getUsers().users.map(u => u.user) + "], роли [" + h.getRoles().roles.map(r => r.role) + "]\n" +
                           "  library: пользователи [" + l.getUsers().users.map(u => u.user) + "]");
  print("До удаления"); show();

  s.dropRole("reader");  s.dropRole("grader");  print("удалены роли reader, grader");
  s.dropUser("ann");  s.dropUser("teacher");     print("удалены пользователи ann, teacher");
  h.dropRole("orders_reader");                   print("удалена роль orders_reader");
  h.dropUser("auditor"); h.dropUser("manager");  print("удалены пользователи auditor, manager");
  l.dropUser("librarian");                       print("удалён пользователь librarian");

  print("После удаления"); show();'
echo "Часть 2 завершена. Чтобы повторить, снова запустите ./01_create_users.sh и далее..."
