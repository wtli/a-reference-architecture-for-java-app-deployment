# Java 应用部署参考

### A Reference Architecture for Java APP Deployment

---

本文是一份 Java 应用部署参考方案，其中包含了部署`.war`格式和`.jar`格式 Java 应用包的方式，文件和文件夹组成格式以及持续集成方案。配套的脚本和 Ansible Playbook 保存在这个 Github Repo 的相应文件中。

**注：本文中涉及的 Java 应用部署方案均不涉及容器相关技术，包括 Docker、Kubernetes 等。**

### 0. 组件和环境

部署应用的操作系统为 Linux；使用的 Java 版本为 Oracle JDK 8，中间件为 Tomcat；使用 Gitlab 作为代码仓库，Jenkins 作为 CI/CD 平台，Ansible 作为发布工具和服务器命令批量执行工具。

- 操作系统：Linux；
- Java 版本：Oracle JDK 7 及以上（推荐 Oracle JDK 8 以上）；
- 中间件：Apache Tomcat 8.0 及以上；
- Java 项目管理：Apache Maven 3 及以上（Gradle 也可，但此处不会示范）。
- 代码库：Gitlab 7 及以上；
- CI/CD：Jenkins 2.0 及以上；
- 批量执行：Ansible 2.4 及以上。

### 1. 原则

为了在实际操作过程中的自由性和规范性中找到平衡，使用这份应用部署规范时需要遵循以下原则。

1. 所有以`.war`格式结尾的 Java 应用包均需要且只能使用 Tomcat 来运行；
2. 所有以`.jar`格式结尾的 Java 应用包均需要且只能使用 Java 程序直接运行；
3. 每台服务器只部署一个 Java 应用；
4. 所有和 Java 应用有关的文件均属于非 root 用户，对应用的维护也只使用非 root 用户；
5. 在环境的安装过程中不使用系统自带的文件夹，也不使用系统自带的包管理器（YUM、APT 等）来安装依赖程序。

本部署参考中的具体实践均假定以上原则在运行环境中成立。如果您的环境中有和以上原则不相容、并且几乎没有可能修改的地方，请勿直接使用本方案进行应用部署。

### 2. 用户设置和文件结构

#### 2.1 用户设置

在安装环境之前，为该环境创建一个专门的应用管理用户和用户组，例如 `appadmin` 或者 `appuser` 等。为简化操作，用户名和用户组名保持一致。

在为该用户设置 UID 和 GID 时，应将该 UID 和 GID 固定为统一数值，以便在跨服务器文件复制过程中保证权限可用；另外，可以考虑在创建 UID 和 GID 时选取一个较大数值，以避免和系统本身的 UID/GID 冲突。

> 如果系统中存在数值较大的 UID/GID ，在查看 `/var/log/lastlog` 文件时可能会发现该文件占用了很大的磁盘空间。实际上，该文件并未占用如此大的空间，详见 [http://www.noah.org/wiki/Lastlog_is_gigantic](http://www.noah.org/wiki/Lastlog_is_gigantic)。

在本文中，我们将该用户和用户组均命名为 `appadmin`，UID 和 GID 均设置为 `1000002`。

#### 2.2 文件结构

##### 2.2.1 JDK

JDK、Tomcat、应用部署包、启动脚本、日志以及 PID 文件均放在一个独立的应用专用文件夹中。这个文件夹及其中包含的所有文件都将属于 2.1 章节指定的应用管理用户。在应用运行环境中，将其设置为 `APP_HOME` 变量；在 Ansible 中，为 `app_home` 变量。

在此，我们将该独立文件夹设置为 `/app`，在后文举例时均会以此作为应用文件夹。

JDK 的存放位置为 `$APP_HOME/jdk1.x.0_xxx`，例如 `/app/jdk1.8.0_172`，并保留版本号。此外，在与 JDK 平级的文件夹中还会创建不含版本号的软链接 `jdk` ，指向 JDK 文件夹 `jdk1.x.0_xxx` 。在创建软链接时，要避免使用绝对路径，以防在应用文件夹改名之后导致软链接失效。

```
[root@localhost app]# ls -l  | grep jdk
lrwxrwxrwx. 1 appadmin appadmin  12 May 30 10:18 jdk -> jdk1.8.0_172
drwxr-xr-x. 8 appadmin appadmin 255 Mar 29 12:55 jdk1.8.0_172
```

##### 2.2.2 Tomcat

**注：Tomcat 只在部署 `.war` 应用包时需要；如果应用包为 `.jar` 格式，则不需要安装 Tomcat。**

Tomcat 的存放位置与 JDK 类似，`$APP_HOME/apache-tomcat-x.x.xx`，例如 `/app/apache-tomcat-8.5.31`，保留版本号。此外，创建软链接 `tomcat` 指向 `apache-tomcat-x.x.xx`。同样要避免使用绝对路径。

```
[root@localhost app]# ls -l | grep tomcat
drwxr-xr-x. 9 appadmin appadmin 160 May 30 10:18 apache-tomcat-8.5.31
lrwxrwxrwx. 1 appadmin appadmin  20 May 30 10:18 tomcat -> apache-tomcat-8.5.31
```

##### 2.2.3 启动和关闭脚本

应用的启动和关闭共涉及 4 个脚本。全部位于应用文件夹中，与 JDK 和 Tomcat 同级。

|脚本|描述|属性|
|:--|:--|:--|
|`app_opts.sh`|存放了应用启动时的自定义参数<br/>（JVM 参数，应用参数等）|`.war`：真实文件<br/>`.jar`：真实文件|
|`setenv.sh`|存放了应用启动时的环境参数<br/>（`APP_HOME`，`JAVA_HOME`，`APP_PID`等）|`.war`：软链接，指向`tomcat/bin/setenv.sh`<br/>`.jar`：真实文件|
|`startup.sh`|启动脚本|`.war`：软链接，指向`tomcat/bin/startup.sh`<br/>`.jar`：真实文件|
|`shutdown.sh`|关闭脚本|`.war`：软链接，指向`tomcat/bin/shutdown.sh`<br/>`.jar`：真实文件|


在 `.war` 环境下如下所示。

```
[root@localhost app]# ls -l | grep sh
-rw-r--r--. 1 appadmin appadmin 368 May 30 16:23 app_opts.sh
lrwxrwxrwx. 1 appadmin appadmin  20 May 30 10:18 setenv.sh -> tomcat/bin/setenv.sh
lrwxrwxrwx. 1 appadmin appadmin  22 May 30 10:18 shutdown.sh -> tomcat/bin/shutdown.sh
lrwxrwxrwx. 1 appadmin appadmin  21 May 30 10:18 startup.sh -> tomcat/bin/startup.sh
```

在 `.jar` 环境下如下所示。

```
[root@localhost app]# ls -l | grep sh
-rw-r--r-- 1 appadmin appadmin  336 May 30 16:12 app_opts.sh
-rw-r--r-- 1 appadmin appadmin  374 May 30 16:12 setenv.sh
-rwxr-xr-x 1 appadmin appadmin  678 May 30 16:12 shutdown.sh
-rwxr-xr-x 1 appadmin appadmin 2344 May 30 16:12 startup.sh
```

##### 2.2.4 应用包存放路径

在 Tomcat 环境中，`.war` 应用包会放在 `tomcat/webapps` 中，Tomcat 发现相应的应用包后会触发解压和部署；在 `.jar` 环境下，应用部署包也需要有特定的位置存放。

为了统一两个环境，方便部署，我们在 `$APP_HOME`下创建了独立的 `webapps`。`.war` 环境下，该路径为软链接，指向 `tomcat/webapps`；`.jar` 环境下，该路径为一个真实文件夹。

`.war` 环境。

```
[root@localhost app]# ls -l | grep webapps
lrwxrwxrwx. 1 appadmin appadmin  14 May 30 10:18 webapps -> tomcat/webapps
```

`.jar` 环境。

```
[root@localhost app]# ls -l | grep webapps
drwxr-xr-x 2 appadmin appadmin    6 May 30 16:12 webapps
```

##### 2.2.5 日志

在 Tomcat 环境中，日志会存放在 `tomcat/logs/` 中，且最主要的日志文件为 `tomcat/logs/catalina.out`；在 `.jar` 环境下，如果不在程序中指定，日志会打印到 `STDOUT`，所以在实际执行时一般使用 `>>` 打印到日志文件。

为了统一，我们在 `$APP_HOME`下创建了独立的 `logs` 文件夹，在其中放置了 `app.log` 文件。`.war` 环境下，该路径为软链接，指向 `../tomcat/logs/catalina.out`；`.jar` 环境下，该路径为一个真实文件。

`.war` 环境。

```
[root@localhost app]# ls -l logs
total 0
lrwxrwxrwx. 1 appadmin appadmin 27 May 30 10:18 app.log -> ../tomcat/logs/catalina.out
```

`.jar` 环境。

```
[root@localhost app]# ls -l logs
total 0
-rw-r--r-- 1 root root 0 May 31 16:39 app.log
```

##### 2.2.6 PID 文件

Tomcat 支持使用 PID 文件来管理 Tomcat 进程，只需要用户指定 PID 文件位置即可；`.jar` 环境下，可以通过启动脚本来创建 PID 文件并加以利用。

我们统一在 `$APP_HOME` 内设置应用 PID 文件，命名为 `app.pid`。在 `.war` 环境和 `.jar` 环境下，该文件均为真实文件，在启动应用时创建，在关闭应用时删除。

### 3. 启动原理

- `app_opts.sh` 脚本在两个环境中完全一样，其中定义了三个变量：`$JVM_OPTS` 用于设置堆内存大小、JMX 端口等；`$JAVA_OPTS` 用于设置一些额外需要传入 Java 执行程序的参数，比如 Apollo 参数等；`$APP_OPTS` 用于设置需要传给应用的参数，比如 Eureka 参数等。

`setenv.sh` 中定义了 JDK 所在的路径 `$JAVA_HOME`。

