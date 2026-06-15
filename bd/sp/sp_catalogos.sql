USE PlanillaObrera;
GO

IF OBJECT_ID('sp_CargarTiposJornada', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposJornada;
GO
CREATE PROCEDURE sp_CargarTiposJornada @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoJornada (IdTipoJornada, Nombre, HoraInicio, HoraFin)
    SELECT
        nodo.value('@id',         'INT'),
        nodo.value('@Nombre',     'VARCHAR(50)'),
        CAST(nodo.value('@HoraInicio', 'VARCHAR(10)') AS TIME),
        CAST(nodo.value('@HoraFin',    'VARCHAR(10)') AS TIME)
    FROM @xmlData.nodes('/Catalogo/TiposDeJornada/TipoDeJornada') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoJornada WHERE IdTipoJornada = nodo.value('@id','INT')
    );
    PRINT 'TiposDeJornada cargados.';
END;
GO
IF OBJECT_ID('sp_CargarPuestos', 'P') IS NOT NULL DROP PROCEDURE sp_CargarPuestos;
GO
CREATE PROCEDURE sp_CargarPuestos @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Puesto (Nombre, SalarioXHora)
    SELECT
        nodo.value('@Nombre',       'VARCHAR(100)'),
        nodo.value('@SalarioXHora', 'DECIMAL(10,2)')
    FROM @xmlData.nodes('/Catalogo/Puestos/dbo.Puesto') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Puesto WHERE Nombre = nodo.value('@Nombre','VARCHAR(100)')
    );
    PRINT 'Puestos cargados.';
END;
GO
IF OBJECT_ID('sp_CargarTiposMovimiento', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposMovimiento;
GO
CREATE PROCEDURE sp_CargarTiposMovimiento @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoMovimiento (IdTipoMovimiento, Nombre, Accion)
    SELECT
        nodo.value('@Id',     'INT'),
        nodo.value('@Nombre', 'VARCHAR(100)'),
        nodo.value('@Accion', 'CHAR(1)')
    FROM @xmlData.nodes('/Catalogo/TiposDeMovimiento/TipoDeMovimiento') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoMovimiento WHERE IdTipoMovimiento = nodo.value('@Id','INT')
    );
    PRINT 'TiposDeMovimiento cargados.';
END;
GO

IF OBJECT_ID('sp_CargarTiposDeduccion', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposDeduccion;
GO
CREATE PROCEDURE sp_CargarTiposDeduccion @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoDeduccion (IdTipoDeduccion, Nombre, EsObligatoria, EsPorcentual, Valor, IdTipoMovimiento)
    SELECT
        nodo.value('@Id',            'INT'),
        nodo.value('@Nombre',        'VARCHAR(100)'),
        nodo.value('@EsObligatoria', 'BIT'),
        nodo.value('@EsPorcentual',  'BIT'),
        nodo.value('@Valor',         'DECIMAL(10,4)'),
        tm.IdTipoMovimiento
    FROM @xmlData.nodes('/Catalogo/TiposDeDeduccion/TipoDeDeduccion') AS T(nodo)
    INNER JOIN dbo.TipoMovimiento tm
        ON tm.Nombre = nodo.value('@dbo.TipoMovimiento','VARCHAR(100)')
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoDeduccion WHERE IdTipoDeduccion = nodo.value('@Id','INT')
    );
    PRINT 'TiposDeDeduccion cargados.';
END;
GO

IF OBJECT_ID('sp_CargarTiposEvento', 'P') IS NOT NULL DROP PROCEDURE sp_CargarTiposEvento;
GO
CREATE PROCEDURE sp_CargarTiposEvento @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TipoEvento (IdTipoEvento, Nombre)
    SELECT
        nodo.value('@Id',     'INT'),
        nodo.value('@Nombre', 'VARCHAR(100)')
    FROM @xmlData.nodes('/Catalogo/TiposdeEvento/dbo.TipoEvento') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.TipoEvento WHERE IdTipoEvento = nodo.value('@Id','INT')
    );
    PRINT 'TiposDeEvento cargados.';
END;
GO

IF OBJECT_ID('sp_CargarUsuariosAdmin', 'P') IS NOT NULL DROP PROCEDURE sp_CargarUsuariosAdmin;
GO
CREATE PROCEDURE sp_CargarUsuariosAdmin @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Usuario (IdUsuario, Username, PasswordHash, Tipo)
    SELECT
        nodo.value('@Id',       'INT'),
        nodo.value('@Username', 'VARCHAR(50)'),
        nodo.value('@pwd',      'VARCHAR(255)'),
        1   
    FROM @xmlData.nodes('/Catalogo/UsuariosAdministrador/dbo.Usuario') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Usuario WHERE IdUsuario = nodo.value('@Id','INT')
    );
    PRINT 'UsuariosAdministrador cargados.';
END;
GO

IF OBJECT_ID('sp_CargarCodigosError', 'P') IS NOT NULL DROP PROCEDURE sp_CargarCodigosError;
GO
CREATE PROCEDURE sp_CargarCodigosError @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.CodigoError (Codigo, Descripcion)
    SELECT
        nodo.value('@Codigo',      'INT'),
        nodo.value('@Descripcion', 'VARCHAR(255)')
    FROM @xmlData.nodes('/Catalogo/CodigosError/Error') AS T(nodo)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.CodigoError WHERE Codigo = nodo.value('@Codigo','INT')
    );
    PRINT 'CodigosError cargados.';
END;
GO

IF OBJECT_ID('sp_CargarCatalogos', 'P') IS NOT NULL DROP PROCEDURE sp_CargarCatalogos;
GO
CREATE PROCEDURE sp_CargarCatalogos @xmlData XML
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC sp_CargarTiposJornada    @xmlData;
        EXEC sp_CargarPuestos         @xmlData;
        EXEC sp_CargarFeriados        @xmlData;
        EXEC sp_CargarTiposEvento     @xmlData;
        EXEC sp_CargarTiposMovimiento @xmlData;      
        EXEC sp_CargarTiposDeduccion  @xmlData;      
        EXEC sp_CargarUsuariosAdmin   @xmlData;
        EXEC sp_CargarCodigosError    @xmlData;

        COMMIT TRANSACTION;
        PRINT 'Carga de catálogos completada exitosamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_CargarCatalogos: %s', 16, 1, @err);
    END CATCH;
END;
GO

PRINT 'SPs de catálogos creados exitosamente.';
GO
