#!/bin/bash
#
# distro_config/install_coding_lib/databases.sh
#
# Database engines + clients. Sourced by install_coding.sh.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "databases.sh is meant to be sourced, not executed." >&2
    exit 1
fi

install_postgresql() {
    print_status "section" "POSTGRESQL"

    if command_exists psql; then
        print_status "info" "PostgreSQL already installed"
        return 0
    fi

    case "$PACKAGE_MANAGER" in
        apt)
            print_status "info" "Adding PostgreSQL repository..."
            run_or_echo sudo apt install -y curl ca-certificates
            run_or_echo sudo install -d /usr/share/postgresql-common/pgdg
            run_or_echo sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

            . /etc/os-release
            sudo sh -c "echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main' > /etc/apt/sources.list.d/pgdg.list"

            print_status "info" "Installing PostgreSQL..."
            sudo apt update
            $INSTALL_CMD postgresql postgresql-contrib
            ;;
        dnf|yum)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql-server postgresql-contrib

            if [ ! -d "/var/lib/pgsql/data/base" ]; then
                print_status "info" "Initializing PostgreSQL database..."
                run_or_echo sudo postgresql-setup --initdb
            fi

            run_or_echo sudo systemctl enable postgresql
            run_or_echo sudo systemctl start postgresql
            ;;
        pacman)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql

            if [ ! -d "/var/lib/postgres/data" ]; then
                print_status "info" "Initializing PostgreSQL database..."
                sudo -u postgres initdb -D /var/lib/postgres/data
            fi

            run_or_echo sudo systemctl enable postgresql
            run_or_echo sudo systemctl start postgresql
            ;;
        zypper)
            print_status "info" "Installing PostgreSQL..."
            $INSTALL_CMD postgresql-server postgresql-contrib

            run_or_echo sudo systemctl enable postgresql
            run_or_echo sudo systemctl start postgresql
            ;;
    esac

    print_status "info" "Installing adminpack extension..."
    if sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS adminpack;" &>> "$LOG_FILE"; then
        print_status "success" "adminpack extension installed"
    else
        print_status "warning" "Could not install adminpack extension (may need manual setup)"
    fi

    print_status "warning" "PostgreSQL installed. You should set a password for the postgres user:"
    print_status "config" "Run: sudo -u postgres psql"
    print_status "config" "Then: ALTER USER postgres WITH PASSWORD 'your_password';"
    print_status "config" "Then: \\q to exit"

    print_status "success" "PostgreSQL installed"
}

install_pgadmin() {
    print_status "section" "PGADMIN4"

    print_status "info" "Adding pgAdmin repository..."
    curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg

    sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list'

    sudo apt update

    print_status "info" "Installing pgAdmin4..."
    run_or_echo sudo apt install -y pgadmin4

    print_status "warning" "To configure pgAdmin4 web mode, run:"
    print_status "config" "sudo /usr/pgadmin4/bin/setup-web.sh"

    print_status "success" "pgAdmin4 installed"
}

install_dbeaver() {
    print_status "section" "DBEAVER"

    if snap list | grep -q dbeaver-ce; then
        print_status "info" "DBeaver already installed"
        return 0
    fi

    print_status "info" "Installing DBeaver Community Edition..."
    run_or_echo sudo snap install dbeaver-ce --classic

    print_status "success" "DBeaver installed"
}

install_sqlite() {
    print_status "section" "SQLITE"

    if command_exists sqlite3; then
        print_status "info" "SQLite already installed"
        return 0
    fi

    print_status "info" "Installing SQLite..."
    install_package "sqlite3" "sqlite3" "sqlite" "sqlite" || {
        print_status "error" "Failed to install SQLite"
        return 1
    }

    print_status "success" "SQLite installed"
}

INSTALL_REGISTRY+=(
    "install_postgresql:PostgreSQL::"
    "install_pgadmin:pgAdmin4:DEV:pgadmin4.desktop"
    "install_dbeaver:DBeaver:DEV:dbeaver-ce_dbeaver-ce.desktop"
    "install_sqlite:SQLite::"
)
