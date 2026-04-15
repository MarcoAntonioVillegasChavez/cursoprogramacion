-- Esquema MySQL para sucursales, usuarios, permisos de usuarios,
-- productos, ventas e inventarios.

CREATE DATABASE IF NOT EXISTS tienda_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE tienda_db;

CREATE TABLE sucursales (
  id_sucursal BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(120) NOT NULL,
  codigo VARCHAR(30) NOT NULL,
  direccion VARCHAR(255) NULL,
  telefono VARCHAR(30) NULL,
  activa TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_sucursales_codigo (codigo),
  KEY idx_sucursales_nombre (nombre)
) ENGINE=InnoDB;

CREATE TABLE usuarios (
  id_usuario BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_sucursal BIGINT UNSIGNED NOT NULL,
  nombre VARCHAR(120) NOT NULL,
  email VARCHAR(150) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  rol ENUM('ADMIN','GERENTE','VENDEDOR','ALMACEN') NOT NULL DEFAULT 'VENDEDOR',
  activo TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_usuarios_email (email),
  KEY idx_usuarios_sucursal (id_sucursal),
  KEY idx_usuarios_rol (rol),
  CONSTRAINT fk_usuarios_sucursal
    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales (id_sucursal)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE permisos_usuarios (
  id_permiso BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_usuario BIGINT UNSIGNED NOT NULL,
  modulo VARCHAR(80) NOT NULL,
  puede_leer TINYINT(1) NOT NULL DEFAULT 0,
  puede_crear TINYINT(1) NOT NULL DEFAULT 0,
  puede_editar TINYINT(1) NOT NULL DEFAULT 0,
  puede_eliminar TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_permiso_usuario_modulo (id_usuario, modulo),
  KEY idx_permisos_modulo (modulo),
  CONSTRAINT fk_permisos_usuario
    FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE productos (
  id_producto BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  sku VARCHAR(60) NOT NULL,
  nombre VARCHAR(150) NOT NULL,
  descripcion VARCHAR(255) NULL,
  precio_compra DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  precio_venta DECIMAL(12,2) NOT NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_productos_sku (sku),
  KEY idx_productos_nombre (nombre),
  KEY idx_productos_activo (activo)
) ENGINE=InnoDB;

CREATE TABLE inventarios (
  id_inventario BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_sucursal BIGINT UNSIGNED NOT NULL,
  id_producto BIGINT UNSIGNED NOT NULL,
  existencia INT NOT NULL DEFAULT 0,
  stock_minimo INT NOT NULL DEFAULT 0,
  stock_maximo INT NOT NULL DEFAULT 0,
  ultima_actualizacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_inventario_sucursal_producto (id_sucursal, id_producto),
  KEY idx_inventario_producto (id_producto),
  CONSTRAINT fk_inventario_sucursal
    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales (id_sucursal)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT fk_inventario_producto
    FOREIGN KEY (id_producto)
    REFERENCES productos (id_producto)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE ventas (
  id_venta BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  id_sucursal BIGINT UNSIGNED NOT NULL,
  id_usuario BIGINT UNSIGNED NOT NULL,
  id_producto BIGINT UNSIGNED NOT NULL,
  fecha_venta DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cantidad INT NOT NULL,
  precio_unitario DECIMAL(12,2) NOT NULL,
  subtotal DECIMAL(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
  total DECIMAL(12,2) NOT NULL,
  metodo_pago ENUM('EFECTIVO','TARJETA','TRANSFERENCIA','OTRO') NOT NULL DEFAULT 'EFECTIVO',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_ventas_fecha (fecha_venta),
  KEY idx_ventas_sucursal (id_sucursal),
  KEY idx_ventas_usuario (id_usuario),
  KEY idx_ventas_producto (id_producto),
  CONSTRAINT fk_ventas_sucursal
    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales (id_sucursal)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT fk_ventas_usuario
    FOREIGN KEY (id_usuario)
    REFERENCES usuarios (id_usuario)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,
  CONSTRAINT fk_ventas_producto
    FOREIGN KEY (id_producto)
    REFERENCES productos (id_producto)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Procedimiento para registrar una venta y descontar inventario
-- en una sola transacción.
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_registrar_venta $$
CREATE PROCEDURE sp_registrar_venta (
  IN p_id_sucursal BIGINT UNSIGNED,
  IN p_id_usuario BIGINT UNSIGNED,
  IN p_id_producto BIGINT UNSIGNED,
  IN p_cantidad INT,
  IN p_precio_unitario DECIMAL(12,2),
  IN p_metodo_pago VARCHAR(20)
)
BEGIN
  DECLARE v_existencia_actual INT;
  DECLARE v_total DECIMAL(12,2);

  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La cantidad debe ser mayor a cero.';
  END IF;

  IF p_precio_unitario IS NULL OR p_precio_unitario < 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El precio unitario no puede ser negativo.';
  END IF;

  IF p_metodo_pago NOT IN ('EFECTIVO','TARJETA','TRANSFERENCIA','OTRO') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Metodo de pago no valido.';
  END IF;

  SET v_total = p_cantidad * p_precio_unitario;

  START TRANSACTION;

  SELECT existencia
    INTO v_existencia_actual
  FROM inventarios
  WHERE id_sucursal = p_id_sucursal
    AND id_producto = p_id_producto
  FOR UPDATE;

  IF v_existencia_actual IS NULL THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No existe inventario para la sucursal y producto indicados.';
  END IF;

  IF v_existencia_actual < p_cantidad THEN
    ROLLBACK;
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Inventario insuficiente para completar la venta.';
  END IF;

  INSERT INTO ventas (
    id_sucursal,
    id_usuario,
    id_producto,
    cantidad,
    precio_unitario,
    total,
    metodo_pago
  )
  VALUES (
    p_id_sucursal,
    p_id_usuario,
    p_id_producto,
    p_cantidad,
    p_precio_unitario,
    v_total,
    p_metodo_pago
  );

  UPDATE inventarios
  SET existencia = existencia - p_cantidad
  WHERE id_sucursal = p_id_sucursal
    AND id_producto = p_id_producto;

  COMMIT;

  SELECT
    LAST_INSERT_ID() AS id_venta,
    v_total AS total_venta;
END $$

DELIMITER ;
