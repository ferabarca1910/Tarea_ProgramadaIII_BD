USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_CargarCatalogos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarCatalogos;
GO

IF OBJECT_ID('dbo.sp_CargarTiposDeduccion', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposDeduccion;
GO

IF OBJECT_ID('dbo.sp_CargarTiposMovimiento', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposMovimiento;
GO

IF OBJECT_ID('dbo.sp_CargarTiposEvento', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposEvento;
GO

IF OBJECT_ID('dbo.sp_CargarUsuarios', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarUsuarios;
GO

IF OBJECT_ID('dbo.sp_CargarCodigosError', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarCodigosError;
GO

IF OBJECT_ID('dbo.sp_CargarFeriados', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarFeriados;
GO

IF OBJECT_ID('dbo.sp_CargarPuestos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarPuestos;
GO

IF OBJECT_ID('dbo.sp_CargarTiposJornada', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposJornada;
GO

CREATE PROCEDURE dbo.sp_CargarTiposJornada
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.TipoJornada (
        IdTipoJornada
      , Nombre
      , HoraInicio
      , HoraFin
    )
    SELECT
        nodo.value('@Id',         'INT')
      , nodo.value('@Nombre',     'VARCHAR(50)')
      , CAST(nodo.value('@HoraInicio', 'VARCHAR(10)') AS TIME)
      , CAST(nodo.value('@HoraFin',    'VARCHAR(10)') AS TIME)
    FROM @inXML.nodes('/Datos/TiposJornada/TipoJornada') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.TipoJornada AS tj
        WHERE (tj.IdTipoJornada = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarPuestos
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Puesto (
        Nombre
      , SalarioXHora
    )
    SELECT
        nodo.value('@Nombre',       'VARCHAR(100)')
      , nodo.value('@SalarioXHora', 'DECIMAL(10,2)')
    FROM @inXML.nodes('/Datos/Puestos/Puesto') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Puesto AS p
        WHERE (p.Nombre = nodo.value('@Nombre', 'VARCHAR(100)'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarFeriados
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Feriado (
        IdFeriado
      , Nombre
      , Fecha
    )
    SELECT
        nodo.value('@Id',     'INT')
      , nodo.value('@Nombre', 'VARCHAR(100)')
      , CONVERT(DATE, nodo.value('@Fecha', 'VARCHAR(10)'), 23)
    FROM @inXML.nodes('/Datos/Feriados/Feriado') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Feriado AS f
        WHERE (f.IdFeriado = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarTiposEvento
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.TipoEvento (
        IdTipoEvento
      , Nombre
    )
    SELECT
        nodo.value('@Id',     'INT')
      , nodo.value('@Nombre', 'VARCHAR(100)')
    FROM @inXML.nodes('/Datos/TiposEvento/TipoEvento') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.TipoEvento AS te
        WHERE (te.IdTipoEvento = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarTiposMovimiento
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.TipoMovimiento (
        IdTipoMovimiento
      , Nombre
      , Accion
    )
    SELECT
        nodo.value('@Id',     'INT')
      , nodo.value('@Nombre', 'VARCHAR(100)')
      , CASE nodo.value('@Accion', 'CHAR(1)')
            WHEN 'C' THEN '+'
            WHEN 'D' THEN '-'
            ELSE nodo.value('@Accion', 'CHAR(1)')
        END
    FROM @inXML.nodes('/Datos/TiposMovimiento/TipoMovimiento') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.TipoMovimiento AS tm
        WHERE (tm.IdTipoMovimiento = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarTiposDeduccion
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.TipoDeduccion (
        IdTipoDeduccion
      , Nombre
      , EsObligatoria
      , EsPorcentual
      , Valor
      , IdTipoMovimiento
    )
    SELECT
        nodo.value('@Id',            'INT')
      , nodo.value('@Nombre',        'VARCHAR(100)')
      , nodo.value('@EsObligatoria', 'BIT')
      , nodo.value('@EsPorcentual',  'BIT')
      , nodo.value('@Valor',         'DECIMAL(10,4)')
      , tm.IdTipoMovimiento
    FROM @inXML.nodes('/Datos/TiposDeduccion/TipoDeduccion') AS x(nodo)
    INNER JOIN dbo.TipoMovimiento AS tm
        ON (tm.Nombre = nodo.value('@TipoMovimiento', 'VARCHAR(100)'))
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.TipoDeduccion AS td
        WHERE (td.IdTipoDeduccion = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarUsuarios
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Usuario (
        IdUsuario
      , Username
      , PasswordHash
      , Tipo
    )
    SELECT
        nodo.value('@Id',           'INT')
      , nodo.value('@Username',     'VARCHAR(50)')
      , nodo.value('@PasswordHash', 'VARCHAR(255)')
      , nodo.value('@Tipo',         'TINYINT')
    FROM @inXML.nodes('/Datos/Usuarios/Usuario') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Usuario AS u
        WHERE (u.IdUsuario = nodo.value('@Id', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarCodigosError
    @inXML XML
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.CodigoError (
        Codigo
      , Descripcion
    )
    SELECT
        nodo.value('@Codigo',      'INT')
      , nodo.value('@Descripcion', 'VARCHAR(255)')
    FROM @inXML.nodes('/Datos/Error/error') AS x(nodo)
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.CodigoError AS ce
        WHERE (ce.Codigo = nodo.value('@Codigo', 'INT'))
    );
END;
GO

CREATE PROCEDURE dbo.sp_CargarCatalogos
    @inXML          XML
  , @outResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC dbo.sp_CargarTiposJornada
            @inXML = @inXML;

        EXEC dbo.sp_CargarPuestos
            @inXML = @inXML;

        EXEC dbo.sp_CargarFeriados
            @inXML = @inXML;

        EXEC dbo.sp_CargarTiposEvento
            @inXML = @inXML;

        EXEC dbo.sp_CargarTiposMovimiento
            @inXML = @inXML;

        EXEC dbo.sp_CargarTiposDeduccion
            @inXML = @inXML;

        EXEC dbo.sp_CargarUsuarios
            @inXML = @inXML;

        EXEC dbo.sp_CargarCodigosError
            @inXML = @inXML;

        COMMIT TRANSACTION;

        PRINT 'Carga de catalogos completada exitosamente.';

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
            ROLLBACK TRANSACTION;

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarCatalogos'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH;
END;
GO

PRINT 'SPs de catalogos creados exitosamente.';
GO
