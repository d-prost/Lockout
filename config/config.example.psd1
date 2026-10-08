@{
    # Lokales, NTFS-geschuetztes Datenverzeichnis; kein UNC-Pfad.
    DataDirectory = 'C:\ProgramData\LockoutMonitor'
    # FQDNs aller zustaendigen Domain Controller explizit eintragen.
    DomainControllers = @('dc01.example.org', 'dc02.example.org')
    # Nur beim ersten Start verwendet; standardmaessig keine Massenrueckschau.
    InitialLookbackMinutes = 15
    Mail = @{
        Enabled = $false
        From = 'lockout@example.org'
        To = @('support@example.org')
        Server = 'smtp.example.org'
        Port = 25
        StartTls = $false
        CredentialFile = ''
        CooldownMinutes = 15
    }
}
