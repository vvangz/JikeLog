import type { UseQueryResult } from '@tanstack/react-query';
import { Button, Result, Skeleton } from 'antd';
import type { ReactNode } from 'react';
import { errorMessage } from '../api/errors';

interface QueryStateProps<T> {
  query: UseQueryResult<T>;
  children: (data: T) => ReactNode;
}

/** 统一的加载与错误状态：加载中显示骨架屏，出错时显示原因和重试按钮。 */
export function QueryState<T>({ query, children }: QueryStateProps<T>) {
  if (query.isPending) return <Skeleton active paragraph={{ rows: 6 }} />;
  if (query.isError) {
    return (
      <Result
        status="error"
        title="加载失败"
        subTitle={errorMessage(query.error)}
        extra={
          <Button type="primary" onClick={() => void query.refetch()}>
            重试
          </Button>
        }
      />
    );
  }
  return <>{children(query.data)}</>;
}
