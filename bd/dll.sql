
--DDL - Control de Asistencia y Planilla Obrera
--Motor: MS SQL Server


USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE (name = 'PlanillaObrera'))
BEGIN
    ALTER DATABASE PlanillaObrera SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PlanillaObrera;
END;
GO

CREATE DATABASE PlanillaObrera;
GO

USE PlanillaObrera;
GO


--TABLAS CATALOGO
--PK fija (viene del XML excepto Puesto que es IDENTITY


CREATE TABLE dbo.TipoJornada (
    IdTipoJornada   INT          NOT NULL
  , Nombre          VARCHAR(50)  NOT NULL
  , HoraInicio      TIME         NOT NULL
  , HoraFin         TIME         NOT NULL
  , CONSTRAINT PK_TipoJornada PRIMARY KEY (IdTipoJornada)
);
GO

--Puesto es IDENTITY porque su PK la genera cada grupo distinto
--El mapeo desde XML se hace por Nombre, no por Id
CREATE TABLE dbo.Puesto (
    IdPuesto        INT           NOT NULL IDENTITY(1,1)
  , Nombre          VARCHAR(100)  NOT NULL
  , SalarioXHora    DECIMAL(10,2) NOT NULL
  , CONSTRAINT PK_Puesto         PRIMARY KEY (IdPuesto)
  , CONSTRAINT UQ_Puesto_Nombre  UNIQUE (Nombre)
);
GO

CREATE TABLE dbo.Feriado (
    IdFeriado   INT          NOT NULL
  , Nombre      VARCHAR(100) NOT NULL
  , Fecha       DATE         NOT NULL
  , CONSTRAINT PK_Feriado PRIMARY KEY (IdFeriado)
);
GO

--Accion: '+' = Credito (suma al salario), '-' = Debito (resta al salario)
CREATE TABLE dbo.TipoMovimiento (
    IdTipoMovimiento    INT          NOT NULL
  , Nombre              VARCHAR(100) NOT NULL
  , Accion              CHAR(1)      NOT NULL
  , CONSTRAINT PK_TipoMovimiento          PRIMARY KEY (IdTipoMovimiento)
  , CONSTRAINT CK_TipoMovimiento_Accion   CHECK (Accion IN ('+', '-'))
);
GO

--EsObligatoria: 1 = se asigna automaticamente al insertar empleado (via trigger)
--EsPorcentual:  1 = se aplica como porcentaje, 0 = monto fijo mensual
CREATE TABLE dbo.TipoDeduccion (
    IdTipoDeduccion     INT           NOT NULL
  , Nombre              VARCHAR(100)  NOT NULL
  , EsObligatoria       BIT           NOT NULL DEFAULT 0
  , EsPorcentual        BIT           NOT NULL DEFAULT 0
  , Valor               DECIMAL(10,4) NOT NULL DEFAULT 0
  , IdTipoMovimiento    INT           NOT NULL
  , CONSTRAINT PK_TipoDeduccion      PRIMARY KEY (IdTipoDeduccion)
  , CONSTRAINT UQ_TipoDeduccion_Nombre UNIQUE (Nombre)
  , CONSTRAINT FK_TipoDeduccion_TipoMovimiento
        FOREIGN KEY (IdTipoMovimiento) REFERENCES dbo.TipoMovimiento(IdTipoMovimiento)
);
GO

CREATE TABLE dbo.TipoEvento (
    IdTipoEvento    INT          NOT NULL
  , Nombre          VARCHAR(100) NOT NULL
  , CONSTRAINT PK_TipoEvento PRIMARY KEY (IdTipoEvento)
);
GO

--Codigos de error del sistema, se cargan desde XML
CREATE TABLE dbo.CodigoError (
    Codigo      INT          NOT NULL
  , Descripcion VARCHAR(255) NOT NULL
  , CONSTRAINT PK_CodigoError PRIMARY KEY (Codigo)
);
GO


--USUARIOS
--Tipo: 1 = Administrador, 2 = Empleado

CREATE TABLE dbo.Usuario (
    IdUsuario       INT          NOT NULL
  , Username        VARCHAR(50)  NOT NULL
  , PasswordHash    VARCHAR(255) NOT NULL
  , Tipo            TINYINT      NOT NULL
  , Activo          BIT          NOT NULL DEFAULT 1
  , CONSTRAINT PK_Usuario         PRIMARY KEY (IdUsuario)
  , CONSTRAINT UQ_Usuario_Username UNIQUE (Username)
  , CONSTRAINT CK_Usuario_Tipo     CHECK (Tipo IN (1, 2))
);
GO


--EMPLEADO
--Sin TipoDocumentoIdentidad ni Departamento (eliminados por el profe)

CREATE TABLE dbo.Empleado (
    IdEmpleado              INT          NOT NULL IDENTITY(1,1)
  , Nombre                  VARCHAR(150) NOT NULL
  , ValorDocumentoIdentidad VARCHAR(30)  NOT NULL
  , IdPuesto                INT          NOT NULL
  , IdUsuario               INT          NOT NULL
  , CuentaBancaria          VARCHAR(30)  NULL
  , FechaIngreso            DATE         NOT NULL
  , Activo                  BIT          NOT NULL DEFAULT 1
  , CONSTRAINT PK_Empleado                PRIMARY KEY (IdEmpleado)
  , CONSTRAINT UQ_Empleado_Documento      UNIQUE (ValorDocumentoIdentidad)
  , CONSTRAINT UQ_Empleado_Nombre         UNIQUE (Nombre)
  , CONSTRAINT FK_Empleado_Puesto         FOREIGN KEY (IdPuesto)   REFERENCES dbo.Puesto(IdPuesto)
  , CONSTRAINT FK_Empleado_Usuario        FOREIGN KEY (IdUsuario)  REFERENCES dbo.Usuario(IdUsuario)
);
GO


--DEDUCCIONES POR EMPLEADO
--FechaFin NULL significa que la deduccion esta vigente
--Al desasociar, se pone FechaFin en lugar de borrar (conserva historial)

CREATE TABLE dbo.DeduccionEmpleado (
    IdDeduccionEmpleado INT           NOT NULL IDENTITY(1,1)
  , IdEmpleado          INT           NOT NULL
  , IdTipoDeduccion     INT           NOT NULL
  , Valor               DECIMAL(10,4) NOT NULL DEFAULT 0
  , FechaInicio         DATE          NOT NULL
  , FechaFin            DATE          NULL
  , CONSTRAINT PK_DeduccionEmpleado       PRIMARY KEY (IdDeduccionEmpleado)
  , CONSTRAINT FK_DE_Empleado             FOREIGN KEY (IdEmpleado)      REFERENCES dbo.Empleado(IdEmpleado)
  , CONSTRAINT FK_DE_TipoDeduccion        FOREIGN KEY (IdTipoDeduccion) REFERENCES dbo.TipoDeduccion(IdTipoDeduccion)
);
GO


--JORNADA DEL EMPLEADO POR SEMANA
--e asigna cada jueves para la semana siguiente (inicia viernes)

CREATE TABLE dbo.JornadaEmpleadoSemana (
    IdJornadaEmpleadoSemana INT  NOT NULL IDENTITY(1,1)
  , IdEmpleado              INT  NOT NULL
  , IdTipoJornada           INT  NOT NULL
  , FechaInicioSemana       DATE NOT NULL
  , CONSTRAINT PK_JornadaEmpleadoSemana   PRIMARY KEY (IdJornadaEmpleadoSemana)
  , CONSTRAINT UQ_JES                     UNIQUE (IdEmpleado, FechaInicioSemana)
  , CONSTRAINT FK_JES_Empleado            FOREIGN KEY (IdEmpleado)    REFERENCES dbo.Empleado(IdEmpleado)
  , CONSTRAINT FK_JES_TipoJornada         FOREIGN KEY (IdTipoJornada) REFERENCES dbo.TipoJornada(IdTipoJornada)
);
GO


--MES PLANILLA
--Va del ultimo viernes del mes anterior al ultimo jueves del mes
--CantidadJueves: 4 o 5, determina como se dividen deducciones fijas

CREATE TABLE dbo.MesPlanilla (
    IdMesPlanilla   INT     NOT NULL IDENTITY(1,1)
  , FechaInicio     DATE    NOT NULL
  , FechaFin        DATE    NOT NULL
  , CantidadJueves  TINYINT NOT NULL
  , Cerrado         BIT     NOT NULL DEFAULT 0
  , CONSTRAINT PK_MesPlanilla PRIMARY KEY (IdMesPlanilla)
);
GO


--SEMANA PLANILLA
--Siempre va de viernes a jueves

CREATE TABLE dbo.SemanaPlanilla (
    IdSemanaPlanilla    INT  NOT NULL IDENTITY(1,1)
  , IdMesPlanilla       INT  NOT NULL
  , FechaInicio         DATE NOT NULL
  , FechaFin            DATE NOT NULL
  , Cerrada             BIT  NOT NULL DEFAULT 0
  , CONSTRAINT PK_SemanaPlanilla  PRIMARY KEY (IdSemanaPlanilla)
  , CONSTRAINT FK_SP_MesPlanilla  FOREIGN KEY (IdMesPlanilla) REFERENCES dbo.MesPlanilla(IdMesPlanilla)
);
GO


--PLANILLA SEMANAL POR EMPLEADO
--Un registro por empleado por semana
--Se crea al abrir la semana con acumuladores en cero

CREATE TABLE dbo.PlanillaSemXEmpleado (
    IdPlanillaSemXEmpleado  INT           NOT NULL IDENTITY(1,1)
  , IdSemanaPlanilla        INT           NOT NULL
  , IdEmpleado              INT           NOT NULL
  , SalarioBruto            DECIMAL(14,2) NOT NULL DEFAULT 0
  , TotalDeducciones        DECIMAL(14,2) NOT NULL DEFAULT 0
  , SalarioNeto             DECIMAL(14,2) NOT NULL DEFAULT 0
  , HorasOrdinarias         INT           NOT NULL DEFAULT 0
  , HorasExtraNormales      INT           NOT NULL DEFAULT 0
  , HorasExtraDobles        INT           NOT NULL DEFAULT 0
  , CONSTRAINT PK_PlanillaSemXEmpleado    PRIMARY KEY (IdPlanillaSemXEmpleado)
  , CONSTRAINT UQ_PSE                     UNIQUE (IdSemanaPlanilla, IdEmpleado)
  , CONSTRAINT FK_PSE_SemanaPlanilla      FOREIGN KEY (IdSemanaPlanilla) REFERENCES dbo.SemanaPlanilla(IdSemanaPlanilla)
  , CONSTRAINT FK_PSE_Empleado            FOREIGN KEY (IdEmpleado)       REFERENCES dbo.Empleado(IdEmpleado)
);
GO


--PLANILLA MENSUAL POR EMPLEADO
--Es la suma de las planillas semanales del mes planilla

CREATE TABLE dbo.PlanillaMesXEmpleado (
    IdPlanillaMesXEmpleado  INT           NOT NULL IDENTITY(1,1)
  , IdMesPlanilla           INT           NOT NULL
  , IdEmpleado              INT           NOT NULL
  , SalarioBrutoMensual     DECIMAL(14,2) NOT NULL DEFAULT 0
  , TotalDeduccionesMensual DECIMAL(14,2) NOT NULL DEFAULT 0
  , SalarioNetoMensual      DECIMAL(14,2) NOT NULL DEFAULT 0
  , CONSTRAINT PK_PlanillaMesXEmpleado    PRIMARY KEY (IdPlanillaMesXEmpleado)
  , CONSTRAINT UQ_PME                     UNIQUE (IdMesPlanilla, IdEmpleado)
  , CONSTRAINT FK_PME_MesPlanilla         FOREIGN KEY (IdMesPlanilla) REFERENCES dbo.MesPlanilla(IdMesPlanilla)
  , CONSTRAINT FK_PME_Empleado            FOREIGN KEY (IdEmpleado)    REFERENCES dbo.Empleado(IdEmpleado)
);
GO


--DETALLE DE DEDUCCIONES POR EMPLEADO POR MES
--Acumula cuanto se dedujo por cada tipo de deduccion en el mes

CREATE TABLE dbo.DeduccionXEmpleadoXMes (
    IdDeduccionXEmpleadoXMes    INT           NOT NULL IDENTITY(1,1)
  , IdPlanillaMesXEmpleado      INT           NOT NULL
  , IdTipoDeduccion             INT           NOT NULL
  , MontoTotal                  DECIMAL(12,2) NOT NULL DEFAULT 0
  , CONSTRAINT PK_DeduccionXEmpleadoXMes      PRIMARY KEY (IdDeduccionXEmpleadoXMes)
  , CONSTRAINT FK_DXExMes_PlanillaMes         FOREIGN KEY (IdPlanillaMesXEmpleado) REFERENCES dbo.PlanillaMesXEmpleado(IdPlanillaMesXEmpleado)
  , CONSTRAINT FK_DXExMes_TipoDeduccion       FOREIGN KEY (IdTipoDeduccion)        REFERENCES dbo.TipoDeduccion(IdTipoDeduccion)
);
GO


--MARCA DE ASISTENCIA
--HoraEntrada y HoraSalida son DATETIME porque la jornada nocturna
--puede iniciar un dia y terminar al dia siguiente

CREATE TABLE dbo.MarcaAsistencia (
    IdMarcaAsistencia   INT      NOT NULL IDENTITY(1,1)
  , IdEmpleado          INT      NOT NULL
  , FechaHoraEntrada    DATETIME NOT NULL
  , FechaHoraSalida     DATETIME NOT NULL
  , FechaOperacion      DATE     NOT NULL
  , CONSTRAINT PK_MarcaAsistencia     PRIMARY KEY (IdMarcaAsistencia)
  , CONSTRAINT FK_MA_Empleado         FOREIGN KEY (IdEmpleado) REFERENCES dbo.Empleado(IdEmpleado)
);
GO


--MOVIMIENTOS DE PLANILLA
--Un movimiento por cada concepto generado por una asistencia
--o por cada deduccion aplicada en el cierre semanal
--IdMarcaAsistencia es NULL para movimientos de deduccion

CREATE TABLE dbo.MovimientoPlanilla (
    IdMovimientoPlanilla    INT           NOT NULL IDENTITY(1,1)
  , IdPlanillaSemXEmpleado  INT           NOT NULL
  , IdTipoMovimiento        INT           NOT NULL
  , IdMarcaAsistencia       INT           NULL
  , Fecha                   DATE          NOT NULL
  , Cantidad                DECIMAL(8,2)  NOT NULL DEFAULT 0
  , Monto                   DECIMAL(12,2) NOT NULL DEFAULT 0
  , CONSTRAINT PK_MovimientoPlanilla          PRIMARY KEY (IdMovimientoPlanilla)
  , CONSTRAINT FK_MP_PlanillaSemXEmpleado     FOREIGN KEY (IdPlanillaSemXEmpleado) REFERENCES dbo.PlanillaSemXEmpleado(IdPlanillaSemXEmpleado)
  , CONSTRAINT FK_MP_TipoMovimiento           FOREIGN KEY (IdTipoMovimiento)       REFERENCES dbo.TipoMovimiento(IdTipoMovimiento)
  , CONSTRAINT FK_MP_MarcaAsistencia          FOREIGN KEY (IdMarcaAsistencia)      REFERENCES dbo.MarcaAsistencia(IdMarcaAsistencia)
);
GO

--BITACORA DE EVENTOS
--Parametros, DatosAntes y DatosDespues se guardan en formato JSON

CREATE TABLE dbo.BitacoraEvento (
    IdBitacoraEvento    INT            NOT NULL IDENTITY(1,1)
  , IdUsuario           INT            NOT NULL
  , IdTipoEvento        INT            NOT NULL
  , IPOrigen            VARCHAR(45)    NOT NULL
  , FechaHora           DATETIME       NOT NULL DEFAULT GETDATE()
  , Parametros          NVARCHAR(MAX)  NULL
  , DatosAntes          NVARCHAR(MAX)  NULL
  , DatosDespues        NVARCHAR(MAX)  NULL
  , CONSTRAINT PK_BitacoraEvento      PRIMARY KEY (IdBitacoraEvento)
  , CONSTRAINT FK_BE_Usuario          FOREIGN KEY (IdUsuario)    REFERENCES dbo.Usuario(IdUsuario)
  , CONSTRAINT FK_BE_TipoEvento       FOREIGN KEY (IdTipoEvento) REFERENCES dbo.TipoEvento(IdTipoEvento)
);
GO

--ERRORES DE BASE DE DATOS
--El bloque CATCH de cada SP inserta aqui los errores

CREATE TABLE dbo.DBErrors (
    IdDBError   INT          NOT NULL IDENTITY(1,1)
  , FechaHora   DATETIME     NOT NULL DEFAULT GETDATE()
  , NombreSP    VARCHAR(200) NULL
  , Mensaje     VARCHAR(MAX) NULL
  , Severidad   INT          NULL
  , Estado      INT          NULL
  , Linea       INT          NULL
  , CONSTRAINT PK_DBErrors PRIMARY KEY (IdDBError)
);
GO

PRINT 'DDL ejecutado exitosamente.';
GO
