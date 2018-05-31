### java-env-installer

这是一份与《Java 应用部署参考》相配套的 Ansible Playbook。

注意：roles/app_home/files 文件夹中的 JDK 文件与 Tomcat 文件并非真实文件，而是做示范的空文件。在使用时，请用真实的 JDK 压缩包和 Tomcat 压缩包替换上述文件。并确保 JDK 和 Tomcat 版本与 group_vars/all 中所标记的版本一致。
