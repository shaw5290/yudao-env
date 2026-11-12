建库,在任意终端执行:
docker exec -it yudao-tdengine taos -s "CREATE DATABASE IF NOT EXISTS ruoyi_vue_pro;"
- 容器名是 ${PROJECT_NAME}-tdengine,如果你的 .env 里设了 PROJECT_NAME,请把 yudao-tdengine 换成实际容器名。不确定就用 docker ps | grep tdengine 查。
- 默认账号是 root/taosdata,命令不需要额外带账号密码。

验证:
docker exec -it yudao-tdengine taos -s "SHOW DATABASES;"
列表里有 ruoyi_vue_pro 就行。
