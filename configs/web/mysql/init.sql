-- MySQL initial setup script for local testing
CREATE DATABASE projectdb;
CREATE USER 'projectuser'@'localhost' IDENTIFIED BY 'StrongPass123!';
GRANT ALL PRIVILEGES ON projectdb.* TO 'projectuser'@'localhost';
FLUSH PRIVILEGES;
