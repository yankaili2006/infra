-- E2B数据库初始化脚本

-- 创建扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 创建用户表
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 创建团队表
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 创建API密钥表
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true
);

-- 创建环境模板表
CREATE TABLE IF NOT EXISTS envs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    dockerfile TEXT,
    build_status VARCHAR(50) DEFAULT 'pending',
    build_logs TEXT,
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    built_at TIMESTAMP WITH TIME ZONE
);

-- 创建沙箱表
CREATE TABLE IF NOT EXISTS sandboxes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sandbox_id VARCHAR(255) UNIQUE NOT NULL,
    env_id UUID REFERENCES envs(id) ON DELETE SET NULL,
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'creating',
    metadata JSONB,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    timeout_seconds INTEGER DEFAULT 300,
    cpu_mhz INTEGER,
    memory_mb INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 创建指标表
CREATE TABLE IF NOT EXISTS metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sandbox_id VARCHAR(255) REFERENCES sandboxes(sandbox_id) ON DELETE CASCADE,
    metric_type VARCHAR(50) NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    labels JSONB
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_sandboxes_team_id ON sandboxes(team_id);
CREATE INDEX IF NOT EXISTS idx_sandboxes_status ON sandboxes(status);
CREATE INDEX IF NOT EXISTS idx_sandboxes_created_at ON sandboxes(created_at);
CREATE INDEX IF NOT EXISTS idx_envs_team_id ON envs(team_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_key ON api_keys(key);
CREATE INDEX IF NOT EXISTS idx_metrics_sandbox_id ON metrics(sandbox_id);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp);

-- 创建函数：更新更新时间戳
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为需要更新时间的表创建触发器
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON teams
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_envs_updated_at BEFORE UPDATE ON envs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sandboxes_updated_at BEFORE UPDATE ON sandboxes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 创建视图：活跃沙箱统计
CREATE OR REPLACE VIEW active_sandboxes_stats AS
SELECT 
    team_id,
    COUNT(*) as total_sandboxes,
    COUNT(CASE WHEN status = 'running' THEN 1 END) as running_sandboxes,
    COUNT(CASE WHEN status = 'creating' THEN 1 END) as creating_sandboxes,
    COUNT(CASE WHEN status = 'paused' THEN 1 END) as paused_sandboxes,
    SUM(memory_mb) as total_memory_mb,
    SUM(cpu_mhz) as total_cpu_mhz
FROM sandboxes
WHERE ended_at IS NULL
GROUP BY team_id;

-- 插入示例数据（仅用于开发和测试）
-- 注意：在生产环境中应删除或注释掉这部分
DO $$
BEGIN
    -- 插入示例团队
    INSERT INTO teams (id, name, slug) VALUES
    ('11111111-1111-1111-1111-111111111111', '默认团队', 'default-team')
    ON CONFLICT (slug) DO NOTHING;

    -- 插入示例用户
    INSERT INTO users (id, email, name) VALUES
    ('22222222-2222-2222-2222-222222222222', 'admin@example.com', '管理员')
    ON CONFLICT (email) DO NOTHING;

    -- 插入示例API密钥
    INSERT INTO api_keys (id, key, name, user_id, team_id) VALUES
    ('33333333-3333-3333-3333-333333333333', 'e2b_53ae1fed82754c17ad8077fbc8bcdd90', '默认密钥', 
     '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111')
    ON CONFLICT (key) DO NOTHING;

    -- 插入示例环境模板
    INSERT INTO envs (id, name, slug, dockerfile, build_status, team_id) VALUES
    ('44444444-4444-4444-4444-444444444444', '基础环境', 'base', 
     'FROM ubuntu:22.04\nRUN apt-get update && apt-get install -y python3 curl wget',
     'built', '11111111-1111-1111-1111-111111111111')
    ON CONFLICT (slug) DO NOTHING;
END $$;