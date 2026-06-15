
--Stored Procedures para carga de catalogos


USE PlanillaObrera;
GO


SP: Cargar Puestos

IF OBJECT_ID('dbo.sp_CargarPuestos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarPuestos;
GO

CREATE PROCEDURE dbo.sp_CargarPuestos
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tPuestos TABLE (
            Nombre       VARCHAR(100)
          , SalarioXHora DECIMAL(10,2)
        );

        INSERT INTO @tPuestos (
            Nombre
          , SalarioXHora
        )
        SELECT
            p.value('@Nombre',       'VARCHAR(100)')
          , p.value('@SalarioXHora', 'DECIMAL(10,2)')
        FROM @inXML.nodes('/Datos/Puestos/Puesto') AS x(p);

        --Insertar solo los que no existen, mapeo por Nombre
        INSERT INTO dbo.Puesto (
            Nombre
          , SalarioXHora
        )
        SELECT
            tp.Nombre
          , tp.SalarioXHora
        FROM @tPuestos AS tp
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Puesto AS pu
            WHERE (pu.Nombre = tp.Nombre)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarPuestos'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar TiposJornada


IF OBJECT_ID('dbo.sp_CargarTiposJornada', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposJornada;
GO

CREATE PROCEDURE dbo.sp_CargarTiposJornada
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tJornadas TABLE (
            IdTipoJornada INT
          , Nombre        VARCHAR(50)
          , HoraInicio    TIME
          , HoraFin       TIME
        );

        INSERT INTO @tJornadas (
            IdTipoJornada
          , Nombre
          , HoraInicio
          , HoraFin
        )
        SELECT
            j.value('@Id',         'INT')
          , j.value('@Nombre',     'VARCHAR(50)')
          , j.value('@HoraInicio', 'TIME')
          , j.value('@HoraFin',    'TIME')
        FROM @inXML.nodes('/Datos/TiposJornada/TipoJornada') AS x(j);

        INSERT INTO dbo.TipoJornada (
            IdTipoJornada
          , Nombre
          , HoraInicio
          , HoraFin
        )
        SELECT
            tj.IdTipoJornada
          , tj.Nombre
          , tj.HoraInicio
          , tj.HoraFin
        FROM @tJornadas AS tj
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.TipoJornada AS t
            WHERE (t.IdTipoJornada = tj.IdTipoJornada)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarTiposJornada'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar Feriados

IF OBJECT_ID('dbo.sp_CargarFeriados', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarFeriados;
GO

CREATE PROCEDURE dbo.sp_CargarFeriados
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tFeriados TABLE (
            IdFeriado INT
          , Nombre    VARCHAR(100)
          , Fecha     DATE
        );

        INSERT INTO @tFeriados (
            IdFeriado
          , Nombre
          , Fecha
        )
        SELECT
            f.value('@Id',     'INT')
          , f.value('@Nombre', 'VARCHAR(100)')
          , f.value('@Fecha',  'DATE')
        FROM @inXML.nodes('/Datos/Feriados/Feriado') AS x(f);

        INSERT INTO dbo.Feriado (
            IdFeriado
          , Nombre
          , Fecha
        )
        SELECT
            tf.IdFeriado
          , tf.Nombre
          , tf.Fecha
        FROM @tFeriados AS tf
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Feriado AS fe
            WHERE (fe.IdFeriado = tf.IdFeriado)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarFeriados'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar TiposEvento

IF OBJECT_ID('dbo.sp_CargarTiposEvento', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposEvento;
GO

CREATE PROCEDURE dbo.sp_CargarTiposEvento
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tEventos TABLE (
            IdTipoEvento INT
          , Nombre       VARCHAR(100)
        );

        INSERT INTO @tEventos (
            IdTipoEvento
          , Nombre
        )
        SELECT
            e.value('@Id',     'INT')
          , e.value('@Nombre', 'VARCHAR(100)')
        FROM @inXML.nodes('/Datos/TiposEvento/TipoEvento') AS x(e);

        INSERT INTO dbo.TipoEvento (
            IdTipoEvento
          , Nombre
        )
        SELECT
            te.IdTipoEvento
          , te.Nombre
        FROM @tEventos AS te
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.TipoEvento AS t
            WHERE (t.IdTipoEvento = te.IdTipoEvento)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarTiposEvento'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar TiposMovimiento

IF OBJECT_ID('dbo.sp_CargarTiposMovimiento', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposMovimiento;
GO

CREATE PROCEDURE dbo.sp_CargarTiposMovimiento
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tMovimientos TABLE (
            IdTipoMovimiento INT
          , Nombre           VARCHAR(100)
          , Accion           CHAR(1)
        );

        INSERT INTO @tMovimientos (
            IdTipoMovimiento
          , Nombre
          , Accion
        )
        SELECT
            m.value('@Id',     'INT')
          , m.value('@Nombre', 'VARCHAR(100)')
          , CASE m.value('@Accion', 'CHAR(1)')
                WHEN 'C' THEN '+'
                WHEN 'D' THEN '-'
                ELSE          '+'
            END
        FROM @inXML.nodes('/Datos/TiposMovimiento/TipoMovimiento') AS x(m);

        INSERT INTO dbo.TipoMovimiento (
            IdTipoMovimiento
          , Nombre
          , Accion
        )
        SELECT
            tm.IdTipoMovimiento
          , tm.Nombre
          , tm.Accion
        FROM @tMovimientos AS tm
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.TipoMovimiento AS t
            WHERE (t.IdTipoMovimiento = tm.IdTipoMovimiento)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarTiposMovimiento'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar TiposDeduccion

IF OBJECT_ID('dbo.sp_CargarTiposDeduccion', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarTiposDeduccion;
GO

CREATE PROCEDURE dbo.sp_CargarTiposDeduccion
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tDeducciones TABLE (
            IdTipoDeduccion INT
          , EsObligatoria   BIT
          , EsPorcentual    BIT
          , Valor           DECIMAL(10,4)
          , NombreTipoMov   VARCHAR(100)
        );

        INSERT INTO @tDeducciones (
            IdTipoDeduccion
          , EsObligatoria
          , EsPorcentual
          , Valor
          , NombreTipoMov
        )
        SELECT
            d.value('@Id',           'INT')
          , d.value('@EsObligatoria','BIT')
          , d.value('@EsPorcentual', 'BIT')
          , d.value('@Valor',        'DECIMAL(10,4)')
          , d.value('@TipoMovimiento','VARCHAR(100)')
        FROM @inXML.nodes('/Datos/TiposDeduccion/TipoDeduccion') AS x(d);

        --FK lookup: obtener IdTipoMovimiento por Nombre
        INSERT INTO dbo.TipoDeduccion (
            IdTipoDeduccion
          , EsObligatoria
          , EsPorcentual
          , Valor
          , IdTipoMovimiento
        )
        SELECT
            td.IdTipoDeduccion
          , td.EsObligatoria
          , td.EsPorcentual
          , td.Valor
          , tm.IdTipoMovimiento
        FROM @tDeducciones AS td
        INNER JOIN dbo.TipoMovimiento AS tm
            ON (tm.Nombre = td.NombreTipoMov)
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.TipoDeduccion AS t
            WHERE (t.IdTipoDeduccion = td.IdTipoDeduccion)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarTiposDeduccion'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar Usuarios

IF OBJECT_ID('dbo.sp_CargarUsuarios', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarUsuarios;
GO

CREATE PROCEDURE dbo.sp_CargarUsuarios
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tUsuarios TABLE (
            IdUsuario    INT
          , Username     VARCHAR(50)
          , PasswordHash VARCHAR(255)
          , Tipo         TINYINT
        );

        INSERT INTO @tUsuarios (
            IdUsuario
          , Username
          , PasswordHash
          , Tipo
        )
        SELECT
            u.value('@Id',           'INT')
          , u.value('@Username',     'VARCHAR(50)')
          , u.value('@PasswordHash', 'VARCHAR(255)')
          , u.value('@Tipo',         'TINYINT')
        FROM @inXML.nodes('/Datos/Usuarios/Usuario') AS x(u);

        INSERT INTO dbo.Usuario (
            IdUsuario
          , Username
          , PasswordHash
          , Tipo
        )
        SELECT
            tu.IdUsuario
          , tu.Username
          , tu.PasswordHash
          , tu.Tipo
        FROM @tUsuarios AS tu
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS us
            WHERE (us.IdUsuario = tu.IdUsuario)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarUsuarios'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Cargar CodigosError

IF OBJECT_ID('dbo.sp_CargarCodigosError', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarCodigosError;
GO

CREATE PROCEDURE dbo.sp_CargarCodigosError
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    BEGIN TRY

        DECLARE @tErrores TABLE (
            Codigo      INT
          , Descripcion VARCHAR(255)
        );

        INSERT INTO @tErrores (
            Codigo
          , Descripcion
        )
        SELECT
            e.value('@Codigo',      'INT')
          , e.value('@Descripcion', 'VARCHAR(255)')
        FROM @inXML.nodes('/Datos/Error/error') AS x(e);

        INSERT INTO dbo.CodigoError (
            Codigo
          , Descripcion
        )
        SELECT
            te.Codigo
          , te.Descripcion
        FROM @tErrores AS te
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.CodigoError AS ce
            WHERE (ce.Codigo = te.Codigo)
        );

    END TRY
    BEGIN CATCH

        SET @outResultCode = 50008;

        INSERT INTO dbo.DBErrors (
            NombreSP
          , Mensaje
          , Severidad
          , Estado
          , Linea
        )
        VALUES (
            'sp_CargarCodigosError'
          , ERROR_MESSAGE()
          , ERROR_SEVERITY()
          , ERROR_STATE()
          , ERROR_LINE()
        );

    END CATCH

END;
GO


--Carga todos los catalogos en orden correcto

IF OBJECT_ID('dbo.sp_CargarCatalogos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CargarCatalogos;
GO

CREATE PROCEDURE dbo.sp_CargarCatalogos
    @inXML          XML
  , @outResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @outResultCode = 0;

    DECLARE @vResultCode INT = 0;

    BEGIN TRY

        --1. Puestos (sin FK, IDENTITY)
        EXEC dbo.sp_CargarPuestos
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --2. TiposJornada (sin FK)
        EXEC dbo.sp_CargarTiposJornada
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --3. Feriados (sin FK)
        EXEC dbo.sp_CargarFeriados
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --4. TiposEvento (sin FK)
        EXEC dbo.sp_CargarTiposEvento
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --5. TiposMovimiento (sin FK) — debe ir ANTES de TiposDeduccion
        EXEC dbo.sp_CargarTiposMovimiento
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --6. TiposDeduccion (FK -> TipoMovimiento)
        EXEC dbo.sp_CargarTiposDeduccion
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --7. Usuarios (sin FK a otras tablas catalogo)
        EXEC dbo.sp_CargarUsuarios
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        --8. CodigosError (sin FK)
        EXEC dbo.sp_CargarCodigosError
            @inXML         = @inXML
          , @outResultCode = @vResultCode OUTPUT;

        IF (@vResultCode <> 0)
        BEGIN
            SET @outResultCode = @vResultCode;
            RETURN;
        END;

        PRINT 'Catalogos cargados exitosamente.';

    END TRY
    BEGIN CATCH

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

    END CATCH

END;
GO

PRINT 'Todos los SPs de catalogos creados exitosamente.';
GO