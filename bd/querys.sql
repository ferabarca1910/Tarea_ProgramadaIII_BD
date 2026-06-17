USE PlanillaObrera;
GO

/*
    Laboratorio de pruebas manuales.
    Este archivo NO es fuente oficial del sistema; sirve para ejecutar
    consultas rapidas durante desarrollo y validacion.
*/

-- Lista todos los stored procedures creados en la BD.
SELECT
    name AS NombreSP
  , create_date AS FechaCreacion
FROM sys.procedures
ORDER BY name;
GO

-- Verificacion general de datos generados por la simulacion.
SELECT 'Empleado' AS Tabla, COUNT(*) AS Filas FROM dbo.Empleado
UNION ALL SELECT 'MarcaAsistencia', COUNT(*) FROM dbo.MarcaAsistencia
UNION ALL SELECT 'MovimientoPlanilla', COUNT(*) FROM dbo.MovimientoPlanilla
UNION ALL SELECT 'SemanaPlanilla', COUNT(*) FROM dbo.SemanaPlanilla
UNION ALL SELECT 'PlanillaSemXEmpleado', COUNT(*) FROM dbo.PlanillaSemXEmpleado
UNION ALL SELECT 'MesPlanilla', COUNT(*) FROM dbo.MesPlanilla
UNION ALL SELECT 'PlanillaMesXEmpleado', COUNT(*) FROM dbo.PlanillaMesXEmpleado
UNION ALL SELECT 'DeduccionXEmpleadoXMes', COUNT(*) FROM dbo.DeduccionXEmpleadoXMes
UNION ALL SELECT 'BitacoraEvento', COUNT(*) FROM dbo.BitacoraEvento
UNION ALL SELECT 'DBErrors', COUNT(*) FROM dbo.DBErrors;
GO

-- Pruebas de consultas administrativas.
DECLARE @outResultCode INT;
DECLARE @outIdUsuario INT;
DECLARE @outTipoUsuario TINYINT;
DECLARE @vIdEmpleado INT;
DECLARE @vValorDocumento VARCHAR(30);

EXEC dbo.sp_Login
    @inUsername = 'admin'
  , @inPassword = 'admin123'
  , @outIdUsuario = @outIdUsuario OUTPUT
  , @outTipoUsuario = @outTipoUsuario OUTPUT
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_Login' AS Prueba
  , @outResultCode AS ResultCode
  , @outIdUsuario AS IdUsuario
  , @outTipoUsuario AS TipoUsuario;

EXEC dbo.sp_ListarEmpleados
    @inSoloActivos = NULL
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ListarEmpleados' AS Prueba
  , @outResultCode AS ResultCode;

EXEC dbo.sp_ListarEmpleadosConFiltro
    @inNombre = 'Carlos'
  , @inValorDocumento = NULL
  , @inSoloActivos = 1
  , @inIdUsuarioConsulta = @outIdUsuario
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ListarEmpleadosConFiltro' AS Prueba
  , @outResultCode AS ResultCode;

SELECT TOP (1)
    @vIdEmpleado = e.IdEmpleado
  , @vValorDocumento = e.ValorDocumentoIdentidad
FROM dbo.Empleado AS e
ORDER BY e.IdEmpleado;

EXEC dbo.sp_ObtenerEmpleado
    @inIdEmpleado = @vIdEmpleado
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ObtenerEmpleado por Id' AS Prueba
  , @outResultCode AS ResultCode
  , @vIdEmpleado AS IdEmpleado;

EXEC dbo.sp_ObtenerEmpleado
    @inValorDocumento = @vValorDocumento
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ObtenerEmpleado por documento' AS Prueba
  , @outResultCode AS ResultCode
  , @vValorDocumento AS ValorDocumento;
GO

-- Pruebas de consultas de empleado.
DECLARE @outResultCode INT;
DECLARE @vIdEmpleado INT;
DECLARE @vIdSemanaPlanilla INT;
DECLARE @vIdMesPlanilla INT;

SELECT TOP (1)
    @vIdEmpleado = pse.IdEmpleado
  , @vIdSemanaPlanilla = pse.IdSemanaPlanilla
FROM dbo.PlanillaSemXEmpleado AS pse
INNER JOIN dbo.MovimientoPlanilla AS mp
    ON (mp.IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado)
WHERE (mp.IdMarcaAsistencia IS NOT NULL)
ORDER BY
    pse.IdSemanaPlanilla DESC
  , pse.IdEmpleado;

SELECT TOP (1)
    @vIdMesPlanilla = pme.IdMesPlanilla
FROM dbo.PlanillaMesXEmpleado AS pme
WHERE (pme.IdEmpleado = @vIdEmpleado)
ORDER BY
    pme.IdMesPlanilla DESC;

SELECT
    @vIdEmpleado AS IdEmpleadoPrueba
  , @vIdSemanaPlanilla AS IdSemanaPlanillaPrueba
  , @vIdMesPlanilla AS IdMesPlanillaPrueba;

EXEC dbo.sp_ConsultarPlanillaSemanal
    @inIdEmpleado = @vIdEmpleado
  , @inIdSemanaPlanilla = @vIdSemanaPlanilla
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ConsultarPlanillaSemanal' AS Prueba
  , @outResultCode AS ResultCode;

EXEC dbo.sp_ConsultarDetalleDeduccionesSemana
    @inIdEmpleado = @vIdEmpleado
  , @inIdSemanaPlanilla = @vIdSemanaPlanilla
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ConsultarDetalleDeduccionesSemana' AS Prueba
  , @outResultCode AS ResultCode;

EXEC dbo.sp_ConsultarDetalleHorasSemana
    @inIdEmpleado = @vIdEmpleado
  , @inIdSemanaPlanilla = @vIdSemanaPlanilla
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ConsultarDetalleHorasSemana' AS Prueba
  , @outResultCode AS ResultCode;

EXEC dbo.sp_ConsultarPlanillaMensual
    @inIdEmpleado = @vIdEmpleado
  , @inIdMesPlanilla = @vIdMesPlanilla
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ConsultarPlanillaMensual' AS Prueba
  , @outResultCode AS ResultCode;

EXEC dbo.sp_ConsultarDetalleDeduccionesMes
    @inIdEmpleado = @vIdEmpleado
  , @inIdMesPlanilla = @vIdMesPlanilla
  , @outResultCode = @outResultCode OUTPUT;

SELECT
    'sp_ConsultarDetalleDeduccionesMes' AS Prueba
  , @outResultCode AS ResultCode;
GO

-- Revision final de errores capturados.
SELECT
    IdDBError
  , FechaHora
  , NombreSP
  , Mensaje
  , Linea
FROM dbo.DBErrors
ORDER BY IdDBError DESC;
GO
