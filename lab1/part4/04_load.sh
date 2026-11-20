#!/bin/bash
# Пункт 4. Нагрузка на учебную базу shop.
# Использование: ./04_load.sh [процессов] [секунд]     (по умолчанию 8 процессов, 180 секунд)
A="mongodb://admin:Admin_123@127.0.0.1:27017/?authSource=admin"
W="${1:-8}"
S="${2:-180}"
adm() { mongosh --quiet "$A" --eval "$1"; }
total() { adm 'const o = db.serverStatus().opcounters; print(o.insert + o.query + o.update + o.delete + o.command)'; }

echo "Подготовка: добавляем 100000 тестовых заказов в shop.orders (в конце будут удалены)"
adm '
  const c = db.getSiblingDB("shop").orders;
  const st = ["new", "paid", "shipped", "done"];
  for (let k = 0; k < 100; k++) {
    const b = [];
    for (let i = 0; i < 1000; i++)
      b.push({customerId: 1 + Math.floor(Math.random() * 200), status: st[Math.floor(Math.random() * 4)],
              total: Math.floor(Math.random() * 5000), created: new Date(), _load: "base"});
    c.insertMany(b);
  }
  print("заказов в коллекции: " + c.countDocuments())'

# Скрипт одного рабочего процесса: цикл из записи, чтения без индекса, агрегации, обновления и удаления
cat > /tmp/worker.js <<'JS'
const secs = __SECS__, wid = "__WID__";
const st = ["new", "paid", "shipped", "done"], rnd = n => Math.floor(Math.random() * n);
const s = db.getSiblingDB("shop"), end = Date.now() + secs * 1000;
while (Date.now() < end) {
  const b = [];
  for (let i = 0; i < 50; i++) b.push({customerId: 1 + rnd(200), status: st[rnd(4)], total: rnd(5000), created: new Date(), _load: wid});
  s.orders.insertMany(b);                                                        // запись
  s.orders.find({status: st[rnd(4)]}).sort({total: -1}).limit(20).toArray();     // чтение без индекса
  s.orders.aggregate([{$match: {status: st[rnd(4)]}}, {$group: {_id: "$customerId", sum: {$sum: "$total"}}},
                      {$sort: {sum: -1}}, {$limit: 10}]).toArray();              // агрегация
  s.orders.updateMany({_load: "base", customerId: 1 + rnd(200), status: "new"}, {$set: {status: "paid"}});
  s.orders.deleteMany({_load: wid, created: {$lt: new Date(Date.now() - 20000)}});
}
JS

echo; echo "До нагрузки"
echo "Пауза 30 секунд: на графиках будет видна спокойная работа сервера"
sleep 30

echo; echo "Нагрузка: $W процессов, $S секунд ($(date +%T))"
for i in $(seq 1 "$W"); do
  sed "s/__SECS__/$S/; s/__WID__/$i/" /tmp/worker.js > /tmp/worker_$i.js
  mongosh --quiet "$A" --file /tmp/worker_$i.js &
done
sleep 10
echo "Подключений во время нагрузки: $(adm 'db.serverStatus().connections.current')"
wait

echo "Удаляем тестовые документы: $(adm 'db.getSiblingDB("shop").orders.deleteMany({_load: {$exists: true}}).deletedCount')"
rm -f /tmp/worker.js /tmp/worker_*.js
echo "Нагрузка закончена, графики должны вернуться к исходному уровню"