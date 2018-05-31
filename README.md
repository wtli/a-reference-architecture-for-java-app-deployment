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

```Bash
[root@localhost app]# ls -l  | grep jdk
lrwxrwxrwx. 1 appadmin appadmin  12 May 30 10:18 jdk -> jdk1.8.0_172
drwxr-xr-x. 8 appadmin appadmin 255 Mar 29 12:55 jdk1.8.0_172
```

##### 2.2.2 Tomcat

**注：Tomcat 只在部署 `.war` 应用包时需要；如果应用包为 `.jar` 格式，则不需要安装 Tomcat。**

Tomcat 的存放位置与 JDK 类似，`$APP_HOME/apache-tomcat-x.x.xx`，例如 `/app/apache-tomcat-8.5.31`，保留版本号。此外，创建软链接 `tomcat` 指向 `apache-tomcat-x.x.xx`。同样要避免使用绝对路径。

```Bash
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

```Bash
[root@localhost app]# ls -l | grep sh
-rw-r--r--. 1 appadmin appadmin 368 May 30 16:23 app_opts.sh
lrwxrwxrwx. 1 appadmin appadmin  20 May 30 10:18 setenv.sh -> tomcat/bin/setenv.sh
lrwxrwxrwx. 1 appadmin appadmin  22 May 30 10:18 shutdown.sh -> tomcat/bin/shutdown.sh
lrwxrwxrwx. 1 appadmin appadmin  21 May 30 10:18 startup.sh -> tomcat/bin/startup.sh
```

在 `.jar` 环境下如下所示。

```Bash
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

### 3. 启动和关闭流程

#### 3.1 通用的自定义参数：`app_opts.sh`

`app_opts.sh` 脚本用来存放启动时所需的自定义参数。该文件在两个环境中通用，位置和模版相同。这个文件中定义了三个变量：`$JVM_OPTS` 用于设置堆内存大小、JMX 端口等；`$JAVA_OPTS` 用于设置一些额外需要传入 Java 执行程序的参数，比如 Apollo 参数等；`$APP_OPTS` 用于设置需要传给应用的参数，比如 Eureka 参数等。

需要注意的是，在 `.war` 应用参数中设置的 `$APP_OPTS` 一般以 “`-D`” 开头；在 `.jar` 应用参数中设置的 `$APP_OPTS` 一般以双横线 “`--`”开头。

#### 3.2 `.war` 应用的启动和关闭流程

`.war`应用的启动流程如下：

1. 执行 `$APP_HOME/startup.sh` 后，该脚本会自动判断自身所处的路径，以确定 Tomcat 文件夹所处的路径，并将该路径设置为 `$CATALINA_HOME` 以便访问 Tomcat 内的其他文件；然后，调用 `$CATALINA_HOME/bin/catalina.sh` 执行启动命令。
2. `$CATALINA_HOME/bin/catalina.sh` 在执行过程中会检查 `$CATALINA_HOME/bin/` 目录下是否存在名为 `setenv.sh` 的文件，如果有则进行 source 操作，以导入 JDK 路径、PID 文件路径和启动参数等信息。
3. 本规范中已经创建了 `$CATALINA_HOME/bin/setenv.sh`。在该文件中，会设置如下变量：
	- 设置 `$APP_HOME` 为 `$CATALINA_HOME` 的父目录；
	- 设置 `$JAVA_HOME` 为 `$APP_HOME/jdk`；
	- 设置 `$CATALINA_PID` 和 `$APP_PID` 为 `$APP_HOME/app.pid`；
	- 设置 `$APP_LOGS` 为 `$APP_HOME/logs/app.log`；
	- 设置 `$WEBAPPS_DIR` 为 `$APP_HOME/webapps`。
	
	在此之后，检查是否存在 `app_opts.sh` 文件，如存在则进行 source 操作，引入 `app_opts.sh` 中的三个变量。最后，设置 `$CATALINA_OPTS` 为 `$JVM_OPTS` 以及 `$APP_OPTS` 的结合，由此导入自定义参数。
4. 启动应用，然后依据 `$CATALINA_PID` 创建 PID 文件。至此完成启动。

`.war` 应用的关闭主要利用了 PID 文件。在关闭过程中，执行了 `shutdown.sh` 后，先确定 `$CATALINA_HOME`，然后确定 `CATALINA_HOME/bin/setenv.sh`，之后确定 `$CATALINA_PID` 等信息，根据 PID 信息关闭对应进程，然后删除 PID 文件。
	

#### 3.3 `.jar` 应用的启动和关闭流程

`.jar` 应用的启动方式如下：

1. 执行 `$APP_HOME/startup.sh`，判断自身所处路径，并设置为 `$APP_HOME`；
2. 检查 $APP_HOME/setenv.sh 是否存在：如果存在则执行 source；不存在则退出；
3. 本规范中已经创建了 `$APP_HOME/setenv.sh`。在该文件中，会设置如下变量：
	- 设置 `$JAVA_HOME` 为 `$APP_HOME/jdk`；
	- 设置 `$APP_PID` 为 `$APP_HOME/app.pid`；
	- 设置 `$APP_LOGS` 为 `$APP_HOME/logs/app.log`；
	- 设置 `$WEBAPPS_DIR` 为 `$APP_HOME/webapps`。
	
	在此之后，检查是否存在 `app_opts.sh` 文件，如存在则进行 source 操作，引入 `app_opts.sh` 中的的三个变量。
4. 在 `$WEBAPPS_DIR` 中查找后缀为 `.jar` 的文件，如果没有找到，或者找到多个均会报错退出。
5. 用获取到的参数、`.jar` 文件和日志路径启动应用并创建 PID。至此完成启动。

`.jar` 应用的关闭也利用了 PID 文件，根据读取到的 PID 信息关闭对应进程，然后删除 PID 文件。 

### 4. 使用 Gitlab、Jenkins 和 Ansible 实现应用持续部署

#### 4.1 概要

Gitlab 中的 Webhook 功能可以在某个项目接到代码推送、合并或添加标签时，将该动作通知到 Gitlab 之外的其他服务；Jenkins 可以利用这一功能，在代码出现变更时收到通知，进而触发代码拉取、应用打包和应用部署等动作。

这一章节主要介绍在以上应用部署模式下，如何使用 Gitlab、Jenkins 和 Ansible 实现应用持续部署。

#### 4.2 项目描述文件

在这里，我们为项目文件安排了一个 INI 格式的项目描述文件，命名为 description.ini，放置在项目的代码库根目录中。该文件的主要内容为应用打包的目标路径，以及不同环境的启动参数。

使用一个专门的“项目描述文件”解决了以下两个问题：

- Java 应用的打包具有不固定性，应用包的目标路径并不统一。将应用包路径预先配置在该文件中，可以让 Jenkins 在打包之后准确获知应用包位置，以便完成部署动作。
- 不同的环境可能使用不同的启动参数，随着项目的开发进展，启动参数可能会频繁变更。使用该文件记录启动参数，可以在不修改服务器文件的情况下加载启动参数，将频繁变动的配置剥离。

`description.ini` 文件的格式如下。

```description.ini
[common]
packaging=war
artifact_target=/my-web-api/target/my-web-api.war

[test]
jvm_opts=-XX:+HeapDumpOnOutOfMemoryError
java_opts=
app_opts=

[staging]
jvm_opts=-XX:+HeapDumpOnOutOfMemoryError
java_opts=
app_opts=

[production]
jvm_opts=-XX:+HeapDumpOnOutOfMemoryError
java_opts=
app_opts=
```

#### 4.3 应用打包

在 Jenkins 中，一般会使用特定 Java 项目采用的项目管理工具进行打包，如 Maven、Gradle 等。打包的方法相对简单和固定，这里暂不赘述。

#### 4.4 应用部署

在测试环境中，应用的部署一般会紧随应用打包进行，通常会使用一些命令批量执行工具，如 Ansible、SaltStack 等。这里我们以 Ansible 为例，简述应用的部署动作。

在 Jenkins 中添加 Ansible 插件后，指定部署需要使用的 Ansible Playbook 和 Inventory 文件。

在 Inventory 文件中列出一套环境中的所有服务器，以应用分组，并且在 Jenkins 项目中指定目标服务器组。

在 Playbook 中，执行以下动作：

1. 确定该应用在 Jenkins 中的目录，然后从 `description.ini` 文件中获取打包路径，以及在该环境下的启动参数。
2. 执行关闭脚本。
3. 部署应用包至目标文件夹。
4. 使用启动参数生成新的 `app_opts.sh` 文件。
5. 执行启动脚本。

完成以上动作后，即完成了一次应用的打包和部署。

### 5. Ansible Playbook

在这个 Github Repo 的 `playbooks` 文件夹中，包含了依据以上参考规范而编写的 Ansible Playbook 以及用于 Jenkins 应用部署的 Playbook。

### 6. 参考

- http://tomcat.apache.org/
- https://docs.ansible.com/
- https://jenkins.io/doc/

### 7. License

MIT
